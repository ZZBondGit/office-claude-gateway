"""Centralized logging setup for the gateway.

All modules should `get_logger(__name__)` from here instead of using
`print()`. The default formatter matches the existing `print()` output
shape (so existing log scrapers keep working) but adds a timestamp prefix
and a level marker.

The module is safe to import multiple times — handlers are added once.
"""
from __future__ import annotations

import logging
import os
import sys
from typing import Final

LOG_LEVEL_ENV: Final[str] = "GATEWAY_LOG_LEVEL"
DEFAULT_LOG_LEVEL: Final[str] = "INFO"

_initialized = False


def _resolve_level() -> int:
    raw = os.getenv(LOG_LEVEL_ENV, DEFAULT_LOG_LEVEL).strip().upper()
    return getattr(logging, raw, logging.INFO)


def setup_logging() -> None:
    """Idempotent global setup. Subsequent calls are no-ops."""
    global _initialized
    if _initialized:
        return

    level = _resolve_level()
    handler = logging.StreamHandler(stream=sys.stderr)
    # Format: 2026-08-11T23:30:00Z [INFO] claude_gateway.providers: message
    handler.setFormatter(
        logging.Formatter(
            fmt="%(asctime)sZ [%(levelname)s] %(name)s: %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    )

    root = logging.getLogger("claude_gateway")
    root.setLevel(level)
    # Avoid duplicate handlers if uvicorn imports us more than once.
    if not any(isinstance(h, logging.StreamHandler) for h in root.handlers):
        root.addHandler(handler)
    root.propagate = False

    _initialized = True


def get_logger(name: str) -> logging.Logger:
    """Return a logger under the `claude_gateway` namespace."""
    setup_logging()
    return logging.getLogger(f"claude_gateway.{name}" if not name.startswith("claude_gateway") else name)