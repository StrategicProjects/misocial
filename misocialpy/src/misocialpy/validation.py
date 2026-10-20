"""Pre-flight validation of themes and field names."""

from __future__ import annotations

import re
from collections.abc import Iterable

from . import _cache
from ._client import HttpError, MdsError, mds_request
from ._format import solr_has


class ValidationError(MdsError, ValueError):
    """Raised when a query parameter is invalid (before any data request)."""


def check_flag(x, arg: str) -> None:
    """A single True or False."""
    if not isinstance(x, bool):
        raise ValidationError(f"`{arg}` must be a single True or False.")


def check_field_names(fields: list[str]) -> list[str]:
    """Local checks of field names (no request), run even with validate=False."""
    from ._format import ID_FIELDS

    if not fields or not all(isinstance(f, str) and f for f in fields):
        raise ValidationError(
            "`fields` must be a non-empty list of field names.\n"
            "  i See mds_fields() for the curated list."
        )
    bad = [f for f in fields if not re.fullmatch(r"[A-Za-z0-9_]+", f)]
    if bad:
        raise ValidationError(
            f"Invalid field name(s): {bad}.\n"
            "  i Field names have only letters, digits and underscores."
        )
    id_asked = [f for f in fields if f in ("id", *ID_FIELDS)]
    if id_asked:
        raise ValidationError(
            f"{id_asked} identify the document and are not measures.\n"
            "  i Locality and period are always returned as columns."
        )
    return fields


def validate_theme(theme: Iterable[str]) -> None:
    from .fields import _themes

    valid = list(_themes()["theme"])
    invalid = [t for t in theme if t not in valid]
    if invalid:
        raise ValidationError(f"Unknown theme(s): {invalid}.\n  i Available themes: {valid}.")


def validate_fields(fields: list[str]) -> None:
    """Validate field names.

    Fields in the curated dictionary are accepted without a request. Any
    other name is checked against the API once per session. ``fl`` silently
    ignores unknown names, so without this check a typo would just return an
    empty result.
    """
    from .fields import _dictionary

    check_field_names(fields)

    known = set(_dictionary()["field"]) | _cache._CACHE.setdefault("valid_fields", set())
    invalid = []
    for f in fields:
        if f in known:
            continue
        if field_exists(f):
            _cache._CACHE["valid_fields"].add(f)
        else:
            invalid.append(f)

    if invalid:
        raise ValidationError(
            f"Field(s) {invalid} not found in the MI Social API.\n"
            "  i See mds_fields() (curated) or mds_api_fields() (all)."
        )


def field_exists(field: str) -> bool:
    """Ask the API whether a field has any value.

    "Defined" is not enough: the Solr schema has dynamic fields (``*_i``,
    ``*_f``, ...), so any name with a type suffix is accepted, even a typo. A
    field exists when at least one document carries it. Names that match no
    dynamic pattern are rejected with HTTP 400 (``"undefined field ..."``).
    """
    from ._response import check_response

    try:
        res = mds_request({"fq": solr_has(field), "rows": 0}, label=f"field check {field}")
    except HttpError as exc:
        if "undefined field" in str(exc):
            return False
        # Network or server failure: re-raise instead of reporting a bad field.
        raise
    check_response(res, kind="count")
    return res["response"]["numFound"] > 0
