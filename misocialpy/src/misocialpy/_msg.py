"""Lightweight console messages, mirroring the R package's cli alerts.

Messages go to stderr and can be silenced with :func:`set_verbose`.
"""

from __future__ import annotations

import sys

_VERBOSE = True


def set_verbose(verbose: bool) -> None:
    """Enable or disable informational messages (success/step/inform)."""
    global _VERBOSE
    _VERBOSE = bool(verbose)


def success(message: str) -> None:
    if _VERBOSE:
        print(f"✔ {message}", file=sys.stderr)


def step(message: str) -> None:
    if _VERBOSE:
        print(f"ℹ {message}", file=sys.stderr)


def inform(message: str) -> None:
    if _VERBOSE:
        print(message, file=sys.stderr)
