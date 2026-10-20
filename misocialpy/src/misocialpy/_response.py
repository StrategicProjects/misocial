"""Response contract, document identity, scalar values and conflicts.

Every response is checked before it is interpreted or cached: a partial,
truncated or malformed answer is an error, never an empty result (deep review
of 0.2.1, items B1, B2, B4, B5, B8 and M5). Mirrors ``R/resposta.R``.
"""

from __future__ import annotations

import math
import re
from typing import Any

from ._client import DataConflictError, ResponseError


def _is_count(x: Any) -> bool:
    return (
        isinstance(x, (int, float))
        and not isinstance(x, bool)
        and math.isfinite(x)
        and x >= 0
        and x == int(x)
    )


def check_response(res: Any, start: int = 0, kind: str = "docs") -> None:
    """Check the shape of a Solr response before using it.

    ``kind`` is ``"docs"`` (a page of documents), ``"count"`` (``rows=0``,
    only ``numFound`` is used) or ``"facet"`` (month counts).
    """
    where = f"page after {start} documents" if kind == "docs" else kind
    resp = res.get("response") if isinstance(res, dict) else None
    if not isinstance(resp, dict):
        raise ResponseError(
            f"Unexpected response from the MI Social API.\n  x No `response` element ({where})."
        )
    header = res.get("responseHeader") or {}
    status = header.get("status")
    if status is not None and status != 0:
        raise ResponseError(
            f"The MI Social API reported an error.\n  x responseHeader status {status} ({where})."
        )
    # Solr flags results cut short by a time limit.
    if header.get("partialResults"):
        raise ResponseError(
            "Partial results from the MI Social API.\n"
            f"  x The server stopped the query before the end ({where}). "
            "Try a smaller selection."
        )
    if not _is_count(resp.get("numFound")):
        raise ResponseError(
            "Unexpected response from the MI Social API.\n"
            f"  x `numFound` must be a non-negative whole number ({where})."
        )
    if kind == "docs":
        docs = resp.get("docs")
        if not isinstance(docs, list) or not all(isinstance(d, dict) for d in docs):
            raise ResponseError(
                "Unexpected response from the MI Social API.\n"
                f"  x `docs` must be a list of documents ({where})."
            )
    if kind == "facet":
        f = ((res.get("facet_counts") or {}).get("facet_fields") or {}).get("anomes_s")
        ok = isinstance(f, list) and len(f) % 2 == 0
        if ok and f:
            months = f[0::2]
            ok = (
                all(is_month(p) for p in months)
                and len(set(months)) == len(months)
                and all(_is_count(n) for n in f[1::2])
            )
        if not ok:
            raise ResponseError(
                "Unexpected response from the MI Social API.\n"
                f"  x Missing or malformed `facet_counts` ({where})."
            )


def is_month(x: Any) -> bool:
    """A month as 'YYYYMM' with the month between 01 and 12 (the one calendar
    rule used for input, documents and facets)."""
    return isinstance(x, str) and bool(re.fullmatch(r"[0-9]{6}", x)) and 1 <= int(x[4:]) <= 12


def check_doc_identity(docs: list[dict[str, Any]]) -> None:
    """Every data document must identify its municipality and month."""
    bad = [
        d
        for d in docs
        if not re.fullmatch(r"[0-9]{6}", str(d.get("codigo_ibge") or ""))
        or not is_month(d.get("anomes_s"))
    ]
    if bad:
        raise ResponseError(
            "Unexpected document in the MI Social response.\n"
            f"  x {len(bad)} document(s) without a valid `codigo_ibge` (6 digits) "
            "or `anomes_s` (YYYYMM, month 01 to 12)."
        )


def doc_value(field: str, value: Any) -> float:
    """One numeric value per document; a list or a text is an error."""
    from .validation import ValidationError

    if isinstance(value, (list, tuple, dict, set)):
        raise ResponseError(
            f"Field `{field}` is not a single value per document.\n"
            "  x A document carries a list or several values."
        )
    try:
        number = float(value)
    except (TypeError, ValueError):
        raise ValidationError(
            f"Field `{field}` is not numeric.\n"
            f"  x The API returned {value!r}.\n"
            "  i misocialpy returns numeric values only."
        ) from None
    # "NaN", "Inf" or "1e999" are numbers that cannot be a measure; accepting
    # them would create missing or infinite values the source never meant.
    if not math.isfinite(number):
        raise ResponseError(
            f"Field `{field}` has non-finite values.\n  x The API returned {value!r}."
        )
    return number


def check_ids(docs: list[dict[str, Any]]) -> None:
    """A document id read twice means the source changed while paging."""
    seen: set = set()
    dup = []
    for d in docs:
        i = d.get("id")
        if i is None:
            continue
        if i in seen:
            dup.append(i)
        seen.add(i)
    if dup:
        raise ResponseError(
            "The MI Social API returned the same document twice.\n"
            f"  x Repeated id(s): {dup[:3]}.\n"
            "  i The source probably changed while it was being read; run the query again."
        )


def dedupe_observations(out):
    """Drop repeated observations; two different values for the same key are an error."""
    key = ["locality_id", "period", "field"]
    dup = out.duplicated(key, keep=False)
    if not dup.any():
        return out
    # A missing value never replaces a known one, whatever the order of the
    # rows: when a key has a known value, its missing rows are dropped first.
    has_known = out[dup & out["value"].notna()].set_index(key).index.unique()
    keys = out.set_index(key).index
    out = out[~(dup & out["value"].isna() & keys.isin(has_known))].reset_index(drop=True)
    dup = out.duplicated(key, keep=False)
    if not dup.any():
        return out
    n_values = out[dup].groupby(key)["value"].nunique(dropna=True)
    conflicts = n_values[n_values > 1]
    if len(conflicts):
        shown = [" / ".join(k) for k in conflicts.index[:3]]
        raise DataConflictError(
            "The MI Social API returned conflicting values.\n"
            f"  x Different values for the same municipality / month / field: {shown}."
        )
    return out.drop_duplicates(key).reset_index(drop=True)
