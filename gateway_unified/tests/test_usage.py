"""Tests for token-usage extraction."""
from claude_gateway.usage import (
    extract_usage_from_message,
    extract_usage_from_sse_event,
    format_usage,
    merge_usage,
)


def test_extract_usage_from_full_message():
    payload = {
        "id": "msg_123",
        "type": "message",
        "usage": {
            "input_tokens": 100,
            "output_tokens": 50,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
        },
    }
    usage = extract_usage_from_message(payload)
    assert usage == {
        "input_tokens": 100,
        "output_tokens": 50,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
    }


def test_extract_usage_missing_keys():
    payload = {"usage": {"input_tokens": 10, "output_tokens": 5}}
    usage = extract_usage_from_message(payload)
    assert usage == {"input_tokens": 10, "output_tokens": 5}


def test_extract_usage_no_usage_block():
    payload = {"id": "msg_123", "type": "message", "content": []}
    assert extract_usage_from_message(payload) is None


def test_extract_usage_non_dict_payload():
    assert extract_usage_from_message("not a dict") is None
    assert extract_usage_from_message(None) is None


def test_extract_usage_drops_unknown_keys():
    payload = {"usage": {"input_tokens": 1, "some_random_field": 999}}
    usage = extract_usage_from_message(payload)
    assert usage == {"input_tokens": 1}


def test_extract_usage_drops_negative_or_non_int():
    payload = {"usage": {"input_tokens": -5, "output_tokens": "50"}}
    usage = extract_usage_from_message(payload)
    # Negative ints dropped, string dropped
    assert usage is None


def test_extract_usage_from_message_delta_event():
    event_data = {
        "type": "message_delta",
        "delta": {
            "stop_reason": "end_turn",
            "usage": {"output_tokens": 42},
        },
    }
    usage = extract_usage_from_sse_event("message_delta", event_data)
    assert usage == {"output_tokens": 42}


def test_extract_usage_ignores_other_event_types():
    event_data = {"delta": {"usage": {"output_tokens": 99}}}
    # content_block_start, content_block_delta, etc. — all should return None
    for ev in ("content_block_start", "content_block_delta", "content_block_stop", "message_start", "ping"):
        assert extract_usage_from_sse_event(ev, event_data) is None


def test_extract_usage_from_message_delta_with_only_delta_no_usage():
    event_data = {"type": "message_delta", "delta": {"stop_reason": "end_turn"}}
    assert extract_usage_from_sse_event("message_delta", event_data) is None


def test_merge_usage_two_dicts():
    a = {"input_tokens": 10, "output_tokens": 20}
    b = {"input_tokens": 5, "output_tokens": 15}
    merged = merge_usage(a, b)
    # merge keeps a key (with zero) once any input had it
    assert merged["input_tokens"] == 15
    assert merged["output_tokens"] == 35
    assert merged["cache_creation_input_tokens"] == 0
    assert merged["cache_read_input_tokens"] == 0


def test_merge_usage_with_none():
    a = {"input_tokens": 10, "output_tokens": 20}
    merged = merge_usage(None, a, None)
    assert merged["input_tokens"] == 10
    assert merged["output_tokens"] == 20


def test_merge_usage_all_none_returns_none():
    assert merge_usage(None, None) is None
    assert merge_usage() is None


def test_merge_usage_with_cache_tokens():
    a = {"input_tokens": 10, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 0}
    b = {"input_tokens": 5, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 50}
    merged = merge_usage(a, b)
    assert merged == {
        "input_tokens": 15,
        "output_tokens": 0,
        "cache_creation_input_tokens": 100,
        "cache_read_input_tokens": 50,
    }


def test_format_usage_full():
    formatted = format_usage({
        "input_tokens": 100,
        "output_tokens": 50,
        "cache_creation_input_tokens": 10,
        "cache_read_input_tokens": 20,
    })
    assert "in=100" in formatted
    assert "out=50" in formatted
    assert "cache_write=10" in formatted
    assert "cache_read=20" in formatted


def test_format_usage_minimal():
    assert format_usage({"input_tokens": 5, "output_tokens": 3}) == "in=5 out=3"


def test_format_usage_none():
    assert format_usage(None) == "n/a"
    assert format_usage({}) == "n/a"