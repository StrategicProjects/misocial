"""Solr filter builders and small helpers shared by the modules."""

from __future__ import annotations

import math
import numbers
from collections.abc import Iterable, Sequence
from datetime import date
from typing import Any

# Columns that identify a document (municipality x month). Everything else in
# a document is a measure.
ID_FIELDS = ["codigo_ibge", "municipio", "sigla_uf", "anomes_s"]


def as_list(x: Any) -> list:
    """A scalar (text, number, numpy scalar) becomes a one-element list; any
    other iterable becomes a list."""
    if isinstance(x, (str, bytes, numbers.Number)) or not hasattr(x, "__iter__"):
        return [x]
    return list(x)


def is_number(x: Any) -> bool:
    """A real number (int, float, numpy number), but not a bool."""
    return isinstance(x, numbers.Real) and not isinstance(x, bool)


def whole_text(x: Any) -> str:
    """Text of a value; a number with a whole value is written without
    decimals (26.0 -> "26"), as in the R package."""
    if is_number(x) and math.isfinite(x) and x == int(x):
        return str(int(x))
    return str(x).strip()


# Years accepted in `periods`: the API starts in 01/2003; anything outside
# 2000 to next year is a typo, not a query.
MIN_YEAR = 2000


def solr_in(field: str, values: Iterable) -> str:
    """Solr disjunction of terms for one field: ``field:(a OR b OR c)``."""
    return f"{field}:({' OR '.join(str(v) for v in values)})"


def solr_has(field: str) -> str:
    """Solr filter matching documents where a field has a value."""
    return f"{field}:[* TO *]"


def chunk_vector(x: Sequence, size: int) -> list[list]:
    """Split a sequence into chunks of at most ``size`` elements."""
    x = list(x)
    if not x:
        return [x]
    return [x[i : i + size] for i in range(0, len(x), size)]


def unit_from_suffix(field: str) -> str:
    """Unit implied by the field-name suffix.

    MI Social field names end with the Solr dynamic-field type: ``_i``/``_l``
    integer count, ``_f`` float (currency in most cases), ``_d`` double
    (percentages and rates). ``_s`` is how the value is stored (a string),
    not what it measures, so its unit is ``"unknown"``.
    """
    for suffix, unit in (("_i", "count"), ("_l", "count"), ("_f", "value"), ("_d", "rate")):
        if field.endswith(suffix):
            return unit
    return "unknown"


def storage_from_suffix(field: str) -> str:
    """Solr storage type implied by the field-name suffix."""
    for suffix, kind in (
        ("_i", "integer"),
        ("_l", "long"),
        ("_f", "float"),
        ("_d", "double"),
        ("_s", "string"),
    ):
        if field.endswith(suffix):
            return kind
    return "untyped"


def period_of(today: date | None = None) -> int:
    """Month of ``today`` (default: now) as a ``YYYYMM`` integer."""
    today = today or date.today()
    return today.year * 100 + today.month
