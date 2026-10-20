"""Explicit rule for months that were not published yet (mirrors R/publicacao.R)."""

from __future__ import annotations

import math
import warnings
from datetime import date

import pandas as pd
from pandas.api.types import is_numeric_dtype

from . import _msg
from ._format import period_of
from ._response import is_month
from .validation import ValidationError


def mds_drop_unpublished(
    data: pd.DataFrame,
    today: date | None = None,
    reference: str = "selection",
    action: str = "drop",
) -> pd.DataFrame:
    """Drop (or flag) months that were not published yet.

    The MI Social API answers ``0``, not "missing", for months whose data has
    not been published. This applies an explicit rule, per field:

    1. months after the current month are **future**;
    2. months after the last month with a non-zero value are **unpublished**;
    3. a field with no non-zero value at all is unpublished entirely.

    The "last month with a non-zero value" comes from ``reference``:

    * ``"selection"`` (default): the localities in ``data``. Needs no request,
      but a small selection can legitimately end in zeros, and those zeros
      would be dropped.
    * ``"brazil"``: every municipality in the country, through
      :func:`mds_periods` (two facet requests per field when not cached).

    A non-zero value in ``data`` is never classified as unpublished. If the
    national reference contradicts the data, it is requested again; if the
    contradiction remains, the month is kept and a warning is raised.

    This is an inference from the published values, not an official
    publication date; ``action="flag"`` keeps every row and adds
    ``publication_status`` (``"published"``, ``"future"``, ``"unpublished"`` or
    ``"missing"``), ``publication_reason`` and ``publication_reference``. Rows
    with a missing ``value`` are never classified as zero.
    """
    if reference not in ("selection", "brazil"):
        raise ValidationError("`reference` must be 'selection' or 'brazil'.")
    if action not in ("drop", "flag"):
        raise ValidationError("`action` must be 'drop' or 'flag'.")
    per, field, today = _normalize_input(data, today)
    if data.empty:
        # Same columns as a non-empty result, so later steps do not depend on
        # whether the query had data.
        if action == "flag":
            data = data.copy()
            for col in ("publication_status", "publication_reason", "publication_reference"):
                data[col] = pd.Series(dtype="object")
        return data

    value = data["value"].to_numpy(dtype=float)
    now = period_of(today)
    future = per > now
    known = ~pd.isna(value)
    nonzero = known & (value != 0) & ~future

    sel = pd.Series(per[nonzero]).groupby(field[nonzero]).max()
    if reference == "brazil":
        last = _last_published_brazil(list(dict.fromkeys(field[~future])), sel)
    else:
        last = sel

    lim = pd.Series(field).map(last).to_numpy(dtype=float)
    unpublished = ~future & known & (pd.isna(lim) | (per > lim))

    status = pd.Series("published", index=data.index)
    status[unpublished] = "unpublished"
    status[~known & ~future] = "missing"
    status[future] = "future"

    if action == "flag":
        out = data.copy()
        out["publication_status"] = status.to_numpy()
        out["publication_reason"] = [_reason(s, li) for s, li in zip(status.to_numpy(), lim)]
        out["publication_reference"] = reference
        return out

    _report(field, per, future, unpublished, reference)
    return data[~(future | unpublished)].reset_index(drop=True)


def _reason(status: str, lim: float):
    if status == "future":
        return "month after today"
    if status == "missing":
        return "value is missing"
    if status == "unpublished":
        if math.isnan(lim):
            return "no non-zero value in the reference"
        return f"after the last non-zero month ({int(lim)})"
    return None


def _normalize_input(data: pd.DataFrame, today):
    """One integer representation of the period, checked as a real month."""
    needed = ["period", "field", "value"]
    missing = [c for c in needed if c not in data.columns]
    if missing:
        raise ValidationError(f"`data` must have columns {needed}. Missing: {missing}.")
    if today is None:
        today = date.today()
    if not isinstance(today, date):
        raise ValidationError("`today` must be a single date.")

    # Only whole numbers become text; 202401.9 stays a float and is rejected
    # (truncating it would classify a period that does not exist).
    period = [
        str(int(p))
        if isinstance(p, (int, float))
        and not isinstance(p, bool)
        and math.isfinite(p)
        and p == int(p)
        else p
        for p in data["period"].astype(object)
    ]
    bad = sorted({str(p) for p in period if not is_month(p)})
    if bad:
        raise ValidationError(
            f"`period` must be 'YYYYMM' (month 01 to 12) with no missing values. Got {bad[:3]}."
        )
    field = data["field"].astype(object).to_numpy()
    if any(pd.isna(f) or not isinstance(f, str) or f == "" for f in field):
        raise ValidationError("`field` must be text with no missing or empty values.")
    if not is_numeric_dtype(data["value"]):
        raise ValidationError("`value` must be numeric.")
    v = data["value"].to_numpy(dtype=float)
    if any(math.isinf(x) for x in v):
        raise ValidationError("`value` must not have infinite values.")
    return pd.array([int(p) for p in period], dtype="int64").to_numpy(), field.astype(str), today


def _last_published_brazil(fields: list[str], selection: pd.Series) -> pd.Series:
    """Last non-zero month per field in Brazil; a contradiction with the data
    is re-read once and, if it remains, the month of the data is kept."""
    from . import periods

    def read(f: str, refresh: bool) -> float:
        p = periods.mds_periods(f, refresh=refresh)
        pub = p.loc[p["n_nonzero"] > 0, "period"]
        return float(pub.astype(int).max()) if len(pub) else float("nan")

    last = {f: read(f, False) for f in fields}
    ahead = [
        f
        for f in fields
        if f in selection.index and (math.isnan(last[f]) or selection[f] > last[f])
    ]
    for f in ahead:
        last[f] = read(f, True)
    still = [f for f in ahead if math.isnan(last[f]) or selection[f] > last[f]]
    if still:
        warnings.warn(
            f"The national reference contradicts the data for {still}; "
            "months with non-zero values were kept.",
            stacklevel=3,
        )
        for f in still:
            last[f] = float(selection[f])
    return pd.Series(last, dtype="float")


def _report(field, per, future, unpublished, reference: str) -> None:
    n_future = int(future.sum())
    if n_future:
        _msg.inform(f"Dropped {n_future} row(s) of future months.")
    if unpublished.any():
        dropped = pd.DataFrame({"field": field[unpublished], "period": per[unpublished]})
        lines = [
            f"• {f}: {', '.join(str(p) for p in sorted(g['period'].unique()))}"
            for f, g in dropped.groupby("field", sort=False)
        ]
        what = (
            "after the last month published in Brazil"
            if reference == "brazil"
            else "of trailing all-zero months"
        )
        _msg.inform(f"Dropped {int(unpublished.sum())} row(s) {what}:\n" + "\n".join(lines))
