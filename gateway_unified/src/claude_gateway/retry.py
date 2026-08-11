"""Retry helper for upstream HTTP calls.

A small, dependency-free retry wrapper for httpx responses. We only retry
transient failures: 5xx server errors, 429 rate-limit, and network-level
errors (connect timeout, read timeout). 4xx client errors are NOT retried —
they indicate a problem with the request that won't fix itself.

Streams are NOT retried (the response is already being consumed).
"""
from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable, TypeVar

import httpx

_logger = logging.getLogger("claude_gateway.retry")

T = TypeVar("T", bound=httpx.Response)

# HTTP status codes that are worth retrying. 429 (rate limit) and 5xx.
RETRYABLE_STATUS_CODES = frozenset({429, 500, 502, 503, 504})

# Default retry policy: 3 attempts, 0.5s base, 2x backoff.
DEFAULT_MAX_ATTEMPTS = 3
DEFAULT_BASE_DELAY_SECONDS = 0.5
DEFAULT_BACKOFF_MULTIPLIER = 2.0


def _is_retryable_response(resp: httpx.Response) -> bool:
    return resp.status_code in RETRYABLE_STATUS_CODES


def _is_retryable_exception(exc: BaseException) -> bool:
    if isinstance(exc, httpx.HTTPError):
        # Connect/read/timeout errors are worth retrying. Write timeouts are
        # trickier (the upstream may already be processing) but for a JSON
        # POST that's idempotent-ish (same body on retry), retrying is OK.
        retryable_types = (
            httpx.ConnectError,
            httpx.ConnectTimeout,
            httpx.ReadError,
            httpx.ReadTimeout,
            httpx.PoolTimeout,
            httpx.RemoteProtocolError,
        )
        return isinstance(exc, retryable_types)
    return False


async def post_json_with_retry(
    request_factory: Callable[[httpx.AsyncClient], Awaitable[httpx.Response]],
    *,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    base_delay_seconds: float = DEFAULT_BASE_DELAY_SECONDS,
    backoff_multiplier: float = DEFAULT_BACKOFF_MULTIPLIER,
    retry_on_status: bool = True,
) -> httpx.Response:
    """POST JSON to upstream with retry on transient failure.

    `request_factory` is a callable that, given an httpx.AsyncClient, builds
    and sends the request. We recreate the AsyncClient each attempt so that
    a broken keep-alive connection on attempt N doesn't poison attempt N+1.
    """
    if max_attempts < 1:
        raise ValueError("max_attempts must be >= 1")

    last_exception: BaseException | None = None
    last_response: httpx.Response | None = None

    for attempt in range(1, max_attempts + 1):
        try:
            async with httpx.AsyncClient() as client:
                resp = await request_factory(client)
            if not retry_on_status or not _is_retryable_response(resp):
                return resp
            last_response = resp
            _logger.warning(
                "[gateway retry] attempt=%s status=%s will_retry=%s",
                attempt,
                resp.status_code,
                attempt < max_attempts,
            )
            if attempt >= max_attempts:
                # No point keeping the connection open; let the caller
                # consume the body via the returned response.
                return last_response
            await resp.aclose()
            last_response = None
        except httpx.HTTPError as exc:
            last_exception = exc
            if not _is_retryable_exception(exc):
                raise
            _logger.warning(
                "[gateway retry] attempt=%s error=%s will_retry=%s",
                attempt,
                exc.__class__.__name__,
                attempt < max_attempts,
            )

        if attempt >= max_attempts:
            break

        # Exponential backoff: base * multiplier^(attempt-1)
        delay = base_delay_seconds * (backoff_multiplier ** (attempt - 1))
        await asyncio.sleep(delay)

    # Exhausted retries. Return whatever we last saw.
    if last_response is not None:
        return last_response
    # last_response is None only if every attempt raised a retryable HTTPError
    # and the retry budget ran out. Re-raise the last one.
    assert last_exception is not None
    raise last_exception