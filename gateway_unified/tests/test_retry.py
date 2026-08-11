"""Tests for the upstream retry helper.

We use `asyncio.run()` per test instead of `@pytest.mark.asyncio` to avoid
pulling in pytest-asyncio as a new dep. The repo only depends on pytest.
"""
from __future__ import annotations

import asyncio

import httpx

from claude_gateway.retry import (
    DEFAULT_BASE_DELAY_SECONDS,
    DEFAULT_MAX_ATTEMPTS,
    RETRYABLE_STATUS_CODES,
    post_json_with_retry,
)


class _FakeAsyncClient:
    """Minimal fake httpx.AsyncClient.

    The retry helper closes the AsyncClient via `async with`, so this fake
    only needs to expose `post()` and the async context-manager protocol.
    Records a `calls` counter so tests can assert on attempt counts.
    """

    def __init__(self, responses):
        self._responses = list(responses)
        self.calls = 0

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def post(self, url, **kwargs):
        self.calls += 1
        if not self._responses:
            raise AssertionError("no scripted response left")
        item = self._responses.pop(0)
        if isinstance(item, BaseException):
            raise item
        return item


class _FakeResponse:
    def __init__(self, status_code, body=b""):
        self.status_code = status_code
        self._body = body
        self.closed = False

    async def aclose(self):
        self.closed = True

    @property
    def text(self) -> str:
        return self._body.decode("utf-8", errors="replace") if isinstance(self._body, bytes) else str(self._body)


def _run(coro):
    return asyncio.run(coro)


def _patch_async_client(monkeypatch, fake):
    """Make httpx.AsyncClient(...) return `fake` (constructed fresh per call)."""
    def factory(*args, **kwargs):
        return fake
    monkeypatch.setattr(httpx, "AsyncClient", factory)


def test_returns_first_success_without_retry(monkeypatch):
    fake = _FakeAsyncClient([_FakeResponse(200, b'{"ok":1}')])
    _patch_async_client(monkeypatch, fake)
    resp = _run(post_json_with_retry(
        lambda c: c.post("http://upstream/", json={}),
        base_delay_seconds=0.0,
    ))
    assert resp.status_code == 200
    assert fake.calls == 1


def test_retries_on_5xx_then_succeeds(monkeypatch):
    fake = _FakeAsyncClient([
        _FakeResponse(503),
        _FakeResponse(502),
        _FakeResponse(200, b"{}"),
    ])
    _patch_async_client(monkeypatch, fake)
    resp = _run(post_json_with_retry(
        lambda c: c.post("http://upstream/", json={}),
        base_delay_seconds=0.0,
    ))
    assert resp.status_code == 200
    assert fake.calls == 3


def test_does_not_retry_4xx_other_than_429(monkeypatch):
    fake = _FakeAsyncClient([_FakeResponse(400)])
    _patch_async_client(monkeypatch, fake)
    resp = _run(post_json_with_retry(
        lambda c: c.post("http://upstream/", json={}),
        base_delay_seconds=0.0,
    ))
    assert resp.status_code == 400
    assert fake.calls == 1


def test_retries_on_429(monkeypatch):
    fake = _FakeAsyncClient([_FakeResponse(429), _FakeResponse(200)])
    _patch_async_client(monkeypatch, fake)
    resp = _run(post_json_with_retry(
        lambda c: c.post("http://upstream/", json={}),
        base_delay_seconds=0.0,
    ))
    assert resp.status_code == 200
    assert fake.calls == 2


def test_retries_on_connect_error_then_succeeds(monkeypatch):
    fake = _FakeAsyncClient([
        httpx.ConnectError("boom"),
        _FakeResponse(200),
    ])
    _patch_async_client(monkeypatch, fake)
    resp = _run(post_json_with_retry(
        lambda c: c.post("http://upstream/", json={}),
        base_delay_seconds=0.0,
    ))
    assert resp.status_code == 200
    assert fake.calls == 2


def test_raises_non_retryable_http_error_immediately(monkeypatch):
    fake = _FakeAsyncClient([httpx.InvalidURL("nope")])
    _patch_async_client(monkeypatch, fake)
    raised = False
    try:
        _run(post_json_with_retry(
            lambda c: c.post("http://upstream/", json={}),
            base_delay_seconds=0.0,
        ))
    except httpx.InvalidURL:
        raised = True
    assert raised
    assert fake.calls == 1


def test_exhausts_retries_and_returns_last_response(monkeypatch):
    fake = _FakeAsyncClient([
        _FakeResponse(503),
        _FakeResponse(503),
        _FakeResponse(503),
    ])
    _patch_async_client(monkeypatch, fake)
    resp = _run(post_json_with_retry(
        lambda c: c.post("http://upstream/", json={}),
        max_attempts=3,
        base_delay_seconds=0.0,
    ))
    assert resp.status_code == 503
    assert fake.calls == 3


def test_default_policy_is_sane():
    assert DEFAULT_MAX_ATTEMPTS >= 1
    assert DEFAULT_BASE_DELAY_SECONDS > 0
    assert 429 in RETRYABLE_STATUS_CODES
    assert 500 in RETRYABLE_STATUS_CODES
    assert 502 in RETRYABLE_STATUS_CODES
    assert 503 in RETRYABLE_STATUS_CODES
    assert 504 in RETRYABLE_STATUS_CODES
    assert 400 not in RETRYABLE_STATUS_CODES
    assert 401 not in RETRYABLE_STATUS_CODES