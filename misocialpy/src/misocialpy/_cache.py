"""In-memory, per-session cache (equivalent to the R package's environment).

Holds localities, field lists, period facets and fields already confirmed to
exist.
"""

from __future__ import annotations

import math
import time
from typing import Any

_CACHE: dict[str, Any] = {}
_STORED_AT: dict[str, float] = {}
_TTL = math.inf


def set_cache_ttl(seconds: float = math.inf) -> None:
    """Set how long, in seconds, a cached result is used (default: the whole
    session). Must be a non-negative number; on error the previous value is
    kept."""
    global _TTL
    if (
        not isinstance(seconds, (int, float))
        or isinstance(seconds, bool)
        or math.isnan(seconds)
        or seconds < 0
    ):
        raise ValueError("`seconds` must be a non-negative number.")
    _TTL = float(seconds)


def _copy(value: Any) -> Any:
    """Independent copy of a cached table, with its attrs.

    Pandas objects are mutable: handing out the stored instance would let an
    edit of a result change the metadata used by later calls (periods feed
    the inference of publication).
    """
    if hasattr(value, "copy") and hasattr(value, "attrs"):
        out = value.copy(deep=True)
        out.attrs = dict(value.attrs)
        return out
    return value


def cache_get(key: str, refresh: bool = False) -> Any:
    """Read a copy of a cached value, unless a refresh is requested."""
    if refresh or key not in _CACHE:
        return None
    if time.monotonic() - _STORED_AT.get(key, 0.0) > _TTL:
        return None
    return _copy(_CACHE[key])


def cache_set(key: str, value: Any) -> Any:
    """Store a copy of a value and return another (only complete, validated
    responses reach here)."""
    from datetime import datetime, timezone

    if hasattr(value, "attrs"):
        value.attrs["retrieved_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    _CACHE[key] = _copy(value)
    _STORED_AT[key] = time.monotonic()
    return _copy(value)


def locality_key(loc: dict) -> str:
    """Canonical key: ['PE', 'PB'] and ['PB', 'PE'] share the cached result."""
    return f"uf={','.join(sorted(loc['states']))};mun={','.join(sorted(loc['municipalities']))}"


def clear_cache() -> None:
    """Remove all cached localities, field lists, periods and field checks.

    Forces fresh API calls on subsequent requests. Public alias:
    :func:`misocialpy.mds_clear_cache`.
    """
    _CACHE.clear()
    _STORED_AT.clear()
    from . import _msg

    _msg.success("MI Social cache cleared.")
