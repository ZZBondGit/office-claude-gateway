"""Extract token usage from Anthropic /v1/messages responses.

Supports both non-streaming (top-level `usage`) and streaming
(`message_delta` events with delta.usage).
"""
from __future__ import annotations

from typing import Any, Dict, Optional


def extract_usage_from_message(payload: Any) -> Optional[Dict[str, int]]:
    """Extract usage from a non-streaming response payload.

    Returns dict with keys: input_tokens, output_tokens, cache_creation_input_tokens,
    cache_read_input_tokens (each present-and-int, or omitted).
    Returns None if no usage block.
    """
    if not isinstance(payload, dict):
        return None
    usage = payload.get("usage")
    return _normalize_usage(usage)


def extract_usage_from_sse_event(event_type: str, event_data: Any) -> Optional[Dict[str, int]]:
    """Extract usage from a streaming SSE event.

    Only `message_delta` events carry final usage (per Anthropic protocol).
    Other events return None.
    """
    if event_type != "message_delta":
        return None
    if not isinstance(event_data, dict):
        return None
    delta = event_data.get("delta")
    if not isinstance(delta, dict):
        return None
    return _normalize_usage(delta.get("usage"))


def _normalize_usage(usage: Any) -> Optional[Dict[str, int]]:
    """Coerce usage values to ints and drop unknowns."""
    if not isinstance(usage, dict):
        return None
    out: Dict[str, int] = {}
    for key in (
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    ):
        value = usage.get(key)
        if isinstance(value, int) and value >= 0:
            out[key] = value
    return out or None


def merge_usage(*usages: Optional[Dict[str, int]]) -> Optional[Dict[str, int]]:
    """Sum multiple usage dicts. Drops None entries. Returns None if all None."""
    keys = ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
    total = {k: 0 for k in keys}
    saw_any = False
    for u in usages:
        if not u:
            continue
        saw_any = True
        for k in keys:
            total[k] += u.get(k, 0)
    return total if saw_any else None


def format_usage(usage: Optional[Dict[str, int]]) -> str:
    """Compact one-line representation for logs."""
    if not usage:
        return "n/a"
    parts = []
    if "input_tokens" in usage:
        parts.append(f"in={usage['input_tokens']}")
    if "output_tokens" in usage:
        parts.append(f"out={usage['output_tokens']}")
    if "cache_creation_input_tokens" in usage:
        parts.append(f"cache_write={usage['cache_creation_input_tokens']}")
    if "cache_read_input_tokens" in usage:
        parts.append(f"cache_read={usage['cache_read_input_tokens']}")
    return " ".join(parts) or "n/a"