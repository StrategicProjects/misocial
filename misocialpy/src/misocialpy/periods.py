"""Periods: parsing of the ``periods`` argument and the facet listing."""

from __future__ import annotations

import math
import re
from datetime import date

import pandas as pd

from . import _cache
from ._client import mds_request
from ._format import MIN_YEAR, as_list, is_number, solr_has, whole_text
from .validation import ValidationError, validate_fields


def mds_periods(field: str, localities="BR", refresh: bool = False) -> pd.DataFrame:
    """List the periods available for a field.

    Uses Solr facets to count, for each month, how many municipalities have a
    value for the field and how many of those values are non-zero.

    The second count matters: the API returns ``0`` for months that were not
    published yet (the BPC series carries zeros for every municipality up to
    the end of the current year). A month where ``n_nonzero`` is 0 for the
    whole selection is almost always unpublished, not a true zero. See
    :func:`mds_drop_unpublished`.

    Cached for the session (``refresh=True`` asks again). Large selections are
    counted in disjoint blocks of at most 200 municipality codes, whose counts
    are summed.

    Returns a DataFrame with columns ``period`` (``"YYYYMM"``),
    ``n_localities`` and ``n_nonzero``, ordered by period;
    ``df.attrs["retrieved_at"]`` keeps the time of the request.
    """
    from .localities import locality_filters, parse_localities
    from .validation import check_flag

    if not isinstance(field, str) or not field:
        raise ValidationError("`field` must be a single field name.")
    check_flag(refresh, "refresh")
    loc = parse_localities(localities)
    validate_fields([field])

    key = f"periods|{field}|{_cache.locality_key(loc)}"
    cached = _cache.cache_get(key, refresh)
    if cached is not None:
        return cached

    filters = locality_filters(loc) or [None]
    has = solr_has(field)
    nonzero_fq = f"{has} AND -{field}:0"

    def counts(fq_field: str, label: str) -> pd.DataFrame:
        parts = [_facet_periods([fq_field] + ([lf] if lf else []), label) for lf in filters]
        x = pd.concat(parts, ignore_index=True)
        if x.empty:
            return pd.DataFrame(
                {"period": pd.Series(dtype="object"), "n": pd.Series(dtype="int64")}
            )
        return x.groupby("period", as_index=False)["n"].sum().sort_values("period")

    def read_pair() -> pd.DataFrame:
        all_vals = counts(has, "periods")
        nonzero = counts(nonzero_fq, "non-zero periods")
        out = all_vals.rename(columns={"n": "n_localities"}).merge(
            nonzero.rename(columns={"n": "n_nonzero"}), on="period", how="outer"
        )
        out["n_nonzero"] = out["n_nonzero"].fillna(0).astype(int)
        return out.sort_values("period").reset_index(drop=True)

    def agree(out: pd.DataFrame) -> pd.Series:
        return out["n_localities"].notna() & (out["n_nonzero"] <= out["n_localities"])

    # The two facets are separate requests and the source can change between
    # them: disagreeing counts are read again once, then an error.
    out = read_pair()
    if not agree(out).all():
        out = read_pair()
    if not agree(out).all():
        from ._client import ResponseError

        bad = out.loc[~agree(out), "period"].tolist()[:3]
        raise ResponseError(
            "The two period counts of the MI Social API disagree.\n"
            f"  x More non-zero values than values in {bad} for `{field}`.\n"
            "  i The source may be updating; run the query again later."
        )
    out["n_localities"] = out["n_localities"].astype(int)
    # Only reached when every facet response passed check_response() and the
    # two counts agree.
    return _cache.cache_set(key, out)


def _facet_periods(fq: list[str], label: str) -> pd.DataFrame:
    from ._response import check_response

    res = mds_request(
        {
            "fq": fq,
            "rows": 0,
            "facet": "true",
            "facet.field": "anomes_s",
            "facet.limit": -1,
            "facet.mincount": 1,
            "facet.sort": "index",
        },
        label=label,
    )
    check_response(res, kind="facet")
    return parse_facet(res["facet_counts"]["facet_fields"]["anomes_s"])


def parse_facet(x: list) -> pd.DataFrame:
    """Turn a Solr facet list (``["a", 1, "b", 2]``) into a DataFrame."""
    return pd.DataFrame({"period": [str(v) for v in x[0::2]], "n": [int(v) for v in x[1::2]]})


def last_months(n: int, today: date | None = None) -> list[str]:
    """Last ``n`` months up to the current month, as ``"YYYYMM"``."""
    today = today or date.today()
    y, m = today.year, today.month
    out = []
    for _ in range(n):
        out.append(f"{y}{m:02d}")
        m -= 1
        if m == 0:
            y, m = y - 1, 12
    return sorted(out)


def parse_periods(periods) -> list[str]:
    """Normalize the ``periods`` argument to a sorted list of ``"YYYYMM"``.

    Accepted forms:

    * ``None`` -> the last 12 months up to the current month
    * a negative integer ``-n`` -> the last ``n`` months up to the current month
    * 4-digit years (``2024``) -> the 12 months of each year
    * 6-digit months (``202401``, ``"202401"``), possibly mixed with years
    """
    if periods is None:
        periods = -12
    values = as_list(periods)
    if not values or any(v is None or (is_number(v) and math.isnan(v)) for v in values):
        raise ValidationError(
            "`periods` must have at least one value and no missing values.\n"
            "  i Use 2024, 202401 or -12."
        )

    numbers = [v for v in values if is_number(v)]
    bad = [v for v in numbers if not math.isfinite(v) or v != int(v)]
    if bad:
        raise ValidationError(f"Numeric `periods` must be whole numbers.\n  x Got {bad}.")
    if any(v < 0 for v in numbers):
        if len(values) != 1:
            raise ValidationError("A negative `periods` (last n months) must be used alone.")
        return last_months(-int(values[0]))

    x = [whole_text(v) for v in values]
    max_year = date.today().year + 1
    years = [v for v in x if re.fullmatch(r"[0-9]{4}", v) and MIN_YEAR <= int(v) <= max_year]
    months = [
        v
        for v in x
        if re.fullmatch(r"[0-9]{6}", v)
        and 1 <= int(v[4:]) <= 12
        and MIN_YEAR <= int(v[:4]) <= max_year
    ]
    invalid = [v for v in x if v not in years and v not in months]
    if invalid:
        raise ValidationError(
            f"Invalid period(s): {invalid}.\n"
            f"  i Use years ({MIN_YEAR} to {max_year}), months as YYYYMM (202401) or a "
            "negative number for the last n months (-12)."
        )
    expanded = [f"{y}{m:02d}" for y in years for m in range(1, 13)]
    return sorted(set(months) | set(expanded))
