"""Localities: code conversion, parsing and the municipality list."""

from __future__ import annotations

import math
import numbers
import re
from collections.abc import Iterable, Sequence
from datetime import date

import pandas as pd

from . import _cache
from ._format import as_list, is_number, whole_text
from .validation import ValidationError

# IBGE state codes (the first two digits of every municipality code).
MDS_STATES: dict[str, int] = {
    "RO": 11,
    "AC": 12,
    "AM": 13,
    "RR": 14,
    "PA": 15,
    "AP": 16,
    "TO": 17,
    "MA": 21,
    "PI": 22,
    "CE": 23,
    "RN": 24,
    "PB": 25,
    "PE": 26,
    "AL": 27,
    "SE": 28,
    "BA": 29,
    "MG": 31,
    "ES": 32,
    "RJ": 33,
    "SP": 35,
    "PR": 41,
    "SC": 42,
    "RS": 43,
    "MS": 50,
    "MT": 51,
    "GO": 52,
    "DF": 53,
}

# Municipalities whose official 7-digit code does not follow the IBGE
# check-digit rule. Checked against the IBGE localities API
# (servicodados.ibge.gov.br/api/v1/localidades/municipios): the rule matches
# 5,562 of 5,571 codes; these are the 9 exceptions.
IBGE_DV_EXCEPTIONS: dict[str, str] = {
    "220191": "2201919",
    "220198": "2201988",
    "220225": "2202251",
    "261153": "2611533",
    "311783": "3117836",
    "315213": "3152131",
    "430587": "4305871",
    "520393": "5203939",
    "520396": "5203962",
}


def _check_digit(code6: str) -> str:
    """IBGE check digit: weights 1,2,1,2,1,2; two-digit products contribute
    the sum of their digits; the digit completes the total to a multiple of 10.
    """
    s = 0
    for i, ch in enumerate(code6):
        p = int(ch) * (1 if i % 2 == 0 else 2)
        s += p // 10 + p % 10
    return str((10 - s % 10) % 10)


def ibge_code7(x: str | int | Iterable) -> str | None | list[str | None]:
    """Convert 6-digit MDS municipality codes to 7-digit IBGE codes.

    The MI Social API identifies municipalities by the first six digits of
    the IBGE code. This restores the official code, using the check-digit rule
    plus the table of exceptions. Inputs that are not 6 digits give ``None``.
    A scalar input returns a scalar.

    >>> ibge_code7(261160)
    '2611606'
    """
    scalar = isinstance(x, (str, bytes, numbers.Number))
    values = as_list(x)
    # Computed once per distinct code: long outputs repeat each municipality
    # in every field and month.
    memo: dict = {}
    out: list[str | None] = []
    for v in values:
        if v not in memo:
            s = None if v is None or (is_number(v) and math.isnan(v)) else whole_text(v)
            if s is None or not re.fullmatch(r"[0-9]{6}", s):
                memo[v] = None
            else:
                memo[v] = IBGE_DV_EXCEPTIONS.get(s, s + _check_digit(s))
        out.append(memo[v])
    return out[0] if scalar else out


def normalize_municipality(x: int | str) -> str:
    """Normalize one municipality code to the 6 digits used by the API."""
    s = "" if x is None else str(x)
    if not re.fullmatch(r"[0-9]{6,7}", s):
        raise ValidationError(
            "`locality` must be a single 6- or 7-digit IBGE municipality code.\n"
            "  i Example: 2611606 or 261160 (Recife)."
        )
    check_dv([s])
    return s[:6]


def check_dv(codes: Iterable[str]) -> None:
    """Reject 7-digit codes whose check digit is wrong.

    Without this, the last digit would simply be dropped and a typo such as
    2611600 would silently query Recife (261160).
    """
    bad = [c for c in codes if len(c) == 7 and ibge_code7(c[:6]) != c]
    if bad:
        raise ValidationError(
            f"Wrong check digit in municipality code(s): {bad}.\n"
            f"  i Did you mean {[ibge_code7(c[:6]) for c in bad]}?"
        )


def states_to_abbr(state: Iterable) -> list[str]:
    """Convert state codes or abbreviations to abbreviations."""
    by_code = {str(v): k for k, v in MDS_STATES.items()}
    out, invalid = [], []
    for s in state:
        s = str(s).upper()
        abbr = s if s in MDS_STATES else by_code.get(s)
        if abbr is None:
            invalid.append(s)
        else:
            out.append(abbr)
    if invalid:
        raise ValidationError(
            f"Unknown state(s): {invalid}.\n"
            "  i Use abbreviations ('PE') or 2-digit IBGE codes (26)."
        )
    return out


def _unique(seq: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(seq))


def parse_localities(localities) -> dict[str, list[str]]:
    """Parse the ``localities`` argument into states and municipality codes.

    Accepts ``"BR"`` (all of Brazil), state abbreviations or 2-digit codes,
    and 6- or 7-digit municipality codes, in any combination. Both lists empty
    means the whole country.
    """
    if localities is None:
        values = []
    else:
        values = as_list(localities)
    # An empty selection must not fall through to "no filter", which would
    # query the whole country.
    if not values or any(
        v is None or (is_number(v) and math.isnan(v)) or str(v).strip() == "" for v in values
    ):
        raise ValidationError(
            "`localities` must have at least one value and no missing values.\n"
            "  i Use 'BR', a state ('PE') or municipality codes."
        )
    x = [whole_text(v).upper() for v in values]

    is_br = [v == "BR" for v in x]
    is_mun = [not b and bool(re.fullmatch(r"[0-9]{6,7}", v)) for v, b in zip(x, is_br)]
    is_state = [
        not b and not m and (v in MDS_STATES or bool(re.fullmatch(r"[0-9]{2}", v)))
        for v, b, m in zip(x, is_br, is_mun)
    ]
    invalid = [v for v, b, m, s in zip(x, is_br, is_mun, is_state) if not (b or m or s)]
    if invalid:
        raise ValidationError(
            f"Invalid locality value(s): {invalid}.\n"
            "  i Use 'BR', state abbreviations ('PE'), 2-digit state codes (26) "
            "or 6/7-digit municipality codes (2611606)."
        )
    # Every value is validated, even when "BR" makes the others redundant.
    states = _unique(states_to_abbr(v for v, s in zip(x, is_state) if s))
    muns = [v for v, m in zip(x, is_mun) if m]
    check_dv(muns)
    if any(is_br):
        return {"states": [], "municipalities": []}
    return {"states": states, "municipalities": _unique(v[:6] for v in muns)}


def localities_period(today: date | None = None) -> str:
    """Month used to list municipalities.

    Every month carries all municipalities; December of the last closed year
    is used so that the names reflect the current territorial division.
    """
    today = today or date.today()
    return f"{today.year - 1}12"


def mds_localities(
    state: str | int | Sequence | None = None,
    period: str | int | None = None,
    refresh: bool = False,
) -> pd.DataFrame:
    """List municipalities available in the API.

    The list is read from one month (by default December of the last closed
    year), paged and checked for completeness; it is cached for the session.

    Parameters
    ----------
    state:
        Optional state abbreviations (``"PE"``) or 2-digit IBGE codes (``26``).
        ``None`` returns all of Brazil.
    period:
        Month (``YYYYMM``) the list is read from. ``None`` uses December of the
        last closed year; the territorial division of that month is returned.
    refresh:
        Ignore the cached list and ask the API again.

    Returns a DataFrame with columns ``locality_id`` (6 digits, as in the
    API), ``ibge_code`` (7 digits), ``locality_name``, ``state`` and
    ``region``; ``df.attrs`` keeps ``period`` and ``retrieved_at``.
    """
    from .periods import parse_periods
    from .validation import check_flag

    check_flag(refresh, "refresh")
    months = [localities_period()] if period is None else parse_periods(period)
    if len(months) != 1:
        raise ValidationError("`period` must be a single month (YYYYMM).")
    month = months[0]
    ufs = None if state is None else states_to_abbr(as_list(state))

    key = f"localities|{month}"
    locs = _cache.cache_get(key, refresh)
    if locs is None:
        locs = _cache.cache_set(key, _fetch_localities(month))

    out = locs.copy() if ufs is None else locs[locs["state"].isin(ufs)].reset_index(drop=True)
    out.attrs = dict(locs.attrs)
    return out


def _fetch_localities(month: str) -> pd.DataFrame:
    """Read and check the municipality list of one month."""
    from ._client import ResponseError
    from ._response import check_doc_identity
    from .data import fetch_all_pages

    docs = fetch_all_pages(
        {
            "fq": f"anomes_s:{month}",
            "fl": "id,codigo_ibge,municipio,sigla_uf,regiao",
            "sort": "id asc",
        },
        label="localities",
    )
    if not docs:
        raise ResponseError(
            f"The MI Social API has no municipality for {month}.\n"
            "  i Choose another month with `period`."
        )
    check_doc_identity([{**d, "anomes_s": month} for d in docs])
    locs = pd.DataFrame(
        {
            "locality_id": [d.get("codigo_ibge") for d in docs],
            "locality_name": [d.get("municipio") for d in docs],
            "state": [d.get("sigla_uf") for d in docs],
            "region": [d.get("regiao") for d in docs],
        }
    )
    dup = locs.loc[locs["locality_id"].duplicated(), "locality_id"].unique().tolist()
    if dup:
        raise ResponseError(
            f"The MI Social API listed a municipality twice.\n  x Repeated code(s): {dup[:3]}."
        )
    locs.insert(1, "ibge_code", ibge_code7(locs["locality_id"]))
    locs = locs.sort_values("locality_id").reset_index(drop=True)
    locs.attrs["period"] = month
    return locs


# Municipality codes per filter query, to keep URLs at a safe length.
MDS_MAX_CODES = 200


def locality_filters(loc: dict[str, list[str]]) -> list[str]:
    """Locality filters without overlap.

    States go in one filter; municipality codes are split in groups of
    ``MDS_MAX_CODES``. A municipality whose state is also requested is left
    out, since the state filter already brings it: the requests are disjoint
    and facet counts can be summed across them.
    """
    from ._format import chunk_vector, solr_in

    by_code = {str(v): k for k, v in MDS_STATES.items()}
    mun = [c for c in loc["municipalities"] if by_code.get(c[:2]) not in loc["states"]]
    out = []
    if loc["states"]:
        out.append(solr_in("sigla_uf", loc["states"]))
    if mun:
        out.extend(solr_in("codigo_ibge", ch) for ch in chunk_vector(mun, MDS_MAX_CODES))
    return out
