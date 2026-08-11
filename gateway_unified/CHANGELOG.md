# Changelog

All notable changes to this project will be documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — 2026-08-11

Production-readiness pass driven by 5 prioritized cleanups.

### Added

- **局域网共享开关（`--lan`）**：默认只监听 `127.0.0.1`（仅本机）；
  CLI 加 `--lan` 即绑定 `0.0.0.0`，允许局域网内其他设备通过
  `http://<本机IP>:<port>` 访问。README 新增「局域网共享」小节，
  含防火墙放行与安全提醒（不要在 `.env` 配 key，建议 auto 模式）。
  顺手修复：`--provider` choices 补上 `minimax`。

- **Token usage logging** (`usage.py`): Extract `input_tokens`,
  `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`
  from non-streaming responses (`payload.usage`) and streaming SSE events
  (`message_delta.delta.usage`). Every request logs
  `[gateway usage] route_kind=… usage=in=X out=Y …` so per-request spend
  is visible in stderr logs. Stream usage is collected from every
  `message_delta` event that surfaces during the SSE loop.

- **Upstream HTTP retry** (`retry.py`): New `post_json_with_retry` helper.
  Retries 5xx, 429, and `httpx` connect/read/pool timeouts with
  exponential backoff (default: 3 attempts, 0.5s × 2×). Non-retryable
  errors (4xx other than 429, invalid URL, write timeout) bubble up
  immediately. Streamed requests bypass retry — once a stream is in
  flight it cannot safely be replayed. Used by the non-streaming primary
  request and by the web-search auto-execute follow-up loop.

- **`tier_count` parameter** on `ProviderConfig`: defaults to 2 (Haiku
  collapses into Sonnet), overridable by subclasses that support an
  independent fast tier. `MiniMaxProvider` sets `tier_count=3` so Haiku
  routes to `MiniMax-M2.5-highspeed` rather than merging into mid.

- **Centralized logging** (`logging_setup.py`): All modules now use
  `logging.getLogger("claude_gateway.<name>")` with a uniform formatter
  `2026-08-11T23:22:35Z [INFO] claude_gateway.providers: message`.
  Configurable via `GATEWAY_LOG_LEVEL` env var (default: INFO).
  Existing log lines (`[gateway route]`, `[gateway sanitize]`, etc.)
  are preserved verbatim so downstream log scrapers keep working.

- **Auto-mode MiniMax routing**: `AutoProvider` now detects `sk-api-*`
  and `sk-cp-*` keys and routes them to `MiniMaxProvider` (PAYG /
  Coding Plan), in addition to the existing `dk-*` (DeepSeek),
  `sk-kimi-*` (Kimi), `sk-mimo-*` / `tp-*` (MiMo), and bare `sk-*`
  (default MiMo) detection. Auto-mode now also reports image support
  for `minimax:*` routes.

### Changed

- **DRY `MiniMaxProvider.route_model`**: Removed a 47-line copy of the
  parent `ProviderConfig.route_model` that duplicated alias mapping,
  prefix matching, and fallback logic. The shared parent method now
  honors the new `tier_count` knob, so MiniMax gets its 3-tier behavior
  "for free" with a single attribute set in `__init__`.

- **Retry behavior on upstream errors**: 429 / 5xx responses are now
  retried 3× before being surfaced to the client. The existing tests
  `test_upstream_429_passthrough` and `test_upstream_error_passthrough`
  have been adjusted to reflect the new (more useful) behavior — the
  last response after retry exhaustion is what the client sees, but the
  attempt count is now > 1.

- **SSE frame handler returns parsed event**: `process_sse_frame` now
  returns a third value (`Optional[Dict[str, Any]]`) — the parsed JSON
  event payload of the current frame. Callers use this to extract
  usage from `message_delta` events without re-parsing the SSE wire
  format. Existing callers that ignored the new value stay correct.

### Test coverage

- New test file `tests/test_retry.py` — 8 tests covering success-on-first
  try, retry-then-success, 4xx non-retry, 429 retry, connect-error
  retry, non-retryable error propagation, retry exhaustion, and policy
  sanity.

- New test file `tests/test_usage.py` — 16 tests covering message-level
  usage extraction, message_delta event extraction, edge cases
  (missing keys, non-int values, negative ints, unknown keys),
  `merge_usage` semantics, and `format_usage` formatting.

- New tests in `tests/test_providers.py::TestAutoProvider`:
  `test_sk_api_prefix_routes_to_minimax_payg` and
  `test_sk_cp_prefix_routes_to_minimax_codingplan` cover the new Auto
  routing for MiniMax keys.

**Test totals**: 83 → 109 passing (+26 new tests). Run time unchanged
(~4.8s for full suite).

### Files touched

- `src/claude_gateway/logging_setup.py` (new)
- `src/claude_gateway/retry.py` (new)
- `src/claude_gateway/usage.py` (new)
- `src/claude_gateway/providers.py` (logging + Auto MiniMax + tier_count
  + DRY MiniMax.route_model)
- `src/claude_gateway/sanitize.py` (logging only)
- `src/claude_gateway/stream.py` (logging + return-tuple signature)
- `src/claude_gateway/web_search.py` (logging only)
- `src/claude_gateway/log_mw.py` (logging only)
- `src/claude_gateway/main.py` (logging + retry integration + usage
  logging on non-streaming, followup, and SSE paths)
- `tests/test_retry.py` (new)
- `tests/test_usage.py` (new)
- `tests/test_providers.py` (2 new tests)