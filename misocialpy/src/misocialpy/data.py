"""Main retrieval: :func:`mds_data` and the theme shortcuts."""

from __future__ import annotations

import warnings
from collections.abc import Sequence
from datetime import datetime, timezone
from typing import Any

import pandas as pd

from ._client import ResponseError, mds_request
from ._format import ID_FIELDS, unit_from_suffix
from ._response import check_doc_identity, check_ids, check_response, dedupe_observations, doc_value
from .fields import _dictionary, mds_fields
from .localities import ibge_code7, locality_filters, parse_localities
from .periods import parse_periods
from .validation import check_field_names, check_flag, validate_fields

# Documents per page. A month of all 5,571 municipalities fits in one page;
# a full year of Brazil (~67,000 documents) with a few fields came back in a
# single 21-second request when tested, so 10,000 keeps each page well under
# the timeout.
MDS_PAGE_SIZE = 10000

COLUMNS = [
    "locality_id",
    "ibge_code",
    "locality_name",
    "state",
    "period",
    "field",
    "label",
    "unit",
    "value",
]


def mds_data(
    fields: Sequence[str],
    periods=None,
    localities="BR",
    validate: bool = True,
) -> pd.DataFrame:
    """Fetch MI Social data as a tidy long DataFrame.

    One row per field x municipality x month in which the API has a value.
    The query is validated before any data request (field names, period
    format, locality codes), then paged through Solr and, when many
    municipality codes are given, split into several requests.

    Values are returned as published. The API answers ``0`` for months that
    were not published yet; use :func:`mds_drop_unpublished` to remove those
    trailing zeros explicitly.

    Parameters
    ----------
    fields:
        Field names. See :func:`mds_fields` (curated) and
        :func:`mds_api_fields`.
    periods:
        ``None`` (last 12 months), ``-n`` (last ``n`` months), years
        (``2024``) and/or months ``YYYYMM`` (``202401``).
    localities:
        ``"BR"``, state abbreviations (``"PE"``) or 2-digit codes (``26``),
        and/or 6- or 7-digit municipality codes (``2611606``).
    validate:
        Check that fields not in the dictionary exist in the API before
        requesting data. Local checks (names, periods, localities) always run.

    Returns a DataFrame with columns ``locality_id``, ``ibge_code``,
    ``locality_name``, ``state``, ``period``, ``field``, ``label``, ``unit``
    and ``value`` (float). The time of the request (UTC, ISO 8601) is kept in
    ``df.attrs["retrieved_at"]``.

    Only numeric fields are supported: a field whose values are text (such as
    ``regiao``) raises :class:`ValidationError`. Every response is checked
    before it is used: a partial or malformed answer, a total that changes
    while paging, a document read twice, a document without municipality or
    month or a field with several values in one document raise
    :class:`ResponseError`; two different values for the same municipality,
    month and field raise :class:`DataConflictError`. A requested
    municipality that returns no document raises a warning. The request
    timeout is set with :func:`set_timeout`.
    """
    # Local checks always run; `validate` only turns off the remote check of
    # field existence.
    check_flag(validate, "validate")
    fields = list(dict.fromkeys([fields] if isinstance(fields, str) else fields))
    check_field_names(fields)
    months = parse_periods(periods)
    loc = parse_localities(localities)
    if validate:
        validate_fields(fields)

    plan = build_query_plan(fields, months, loc)
    docs: list[dict[str, Any]] = []
    for i, query in enumerate(plan, start=1):
        label = "data" if len(plan) == 1 else f"data (request {i}/{len(plan)})"
        docs.extend(fetch_all_pages(query, label=label))

    out = dedupe_observations(parse_docs(docs, fields))
    _warn_missing_municipalities(loc, docs)
    out.attrs["retrieved_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    return out


def build_query_plan(fields: list[str], months: list[str], loc: dict[str, list[str]]):
    """One query per locality filter (see :func:`locality_filters`).

    Months are passed as an explicit ``OR`` list. The document ``id`` is
    requested to detect documents read twice while paging.
    """
    from ._format import solr_in

    fl = ",".join(dict.fromkeys(["id", *ID_FIELDS, *fields]))
    month_fq = solr_in("anomes_s", months)
    filters = locality_filters(loc) or [None]
    return [{"fq": [month_fq] + ([lf] if lf else []), "fl": fl, "sort": "id asc"} for lf in filters]


def fetch_all_pages(query: dict[str, Any], label: str = "data") -> list[dict[str, Any]]:
    """Page through a Solr query until all documents are read.

    Pages are read with Solr's ``cursorMark``, which walks the results by the
    sort key (``id``) instead of by position. ``numFound`` must stay the same
    on every page and no document id may repeat; reading stops as soon as
    ``numFound`` documents were read, and fewer than that is an error.
    """
    # cursorMark requires the sort to include the unique key.
    query = {"sort": "id asc", **query}
    docs: list[dict[str, Any]] = []
    cursor = "*"
    total = None
    while True:
        res = mds_request({**query, "cursorMark": cursor, "rows": MDS_PAGE_SIZE}, label=label)
        check_response(res, len(docs), "docs")
        page = res["response"]["docs"]
        n = res["response"]["numFound"]
        if total is None:
            total = n
        if n != total:
            raise ResponseError(
                "The MI Social API changed while it was being read.\n"
                f"  x `numFound` went from {total} to {n} after {len(docs)} documents.\n"
                "  i Run the query again."
            )
        docs.extend(page)
        if len(docs) > total:
            raise ResponseError(
                "Unexpected response from the MI Social API.\n"
                f"  x {len(docs)} documents read, but `numFound` is {total}."
            )
        if len(docs) >= total:
            break
        nxt = res.get("nextCursorMark")
        # The cursor stops moving at the end of the results: if that happens
        # before numFound, part of the data is missing.
        if not isinstance(nxt, str) or nxt == cursor or not page:
            raise ResponseError(
                "Incomplete response from the MI Social API.\n"
                f"  x Read {len(docs)} of {total} documents; the next page is missing or empty."
            )
        cursor = nxt
    check_ids(docs)
    return docs


def _warn_missing_municipalities(loc: dict[str, list[str]], docs: list[dict[str, Any]]) -> None:
    """Warn about requested municipalities that returned no document."""
    if not loc["municipalities"]:
        return
    got = {d.get("codigo_ibge") for d in docs}
    missing = [c for c in loc["municipalities"] if c not in got]
    if missing:
        warnings.warn(
            f"No document in the MI Social API for municipality(ies) {ibge_code7(missing)} "
            "in the requested months. Check the code with mds_localities().",
            stacklevel=3,
        )


def parse_docs(docs: list[dict[str, Any]], fields: list[str]) -> pd.DataFrame:
    """Flatten Solr documents into the long output format.

    Documents are sparse: a field that was not published for a month is
    absent from that document, so it produces no row. Each document must
    identify its municipality and month and carry at most one value per field.
    """
    if not docs:
        return empty_result()
    check_doc_identity(docs)
    rows = [
        (
            d.get("codigo_ibge"),
            d.get("municipio"),
            d.get("sigla_uf"),
            d.get("anomes_s"),
            f,
            doc_value(f, d[f]),
        )
        for f in fields
        for d in docs
        if d.get(f) is not None
    ]
    if not rows:
        return empty_result()

    out = pd.DataFrame(
        rows, columns=["locality_id", "locality_name", "state", "period", "field", "value"]
    )
    # A field may belong to more than one theme (CRAS and CREAS are in both
    # bpc_suas and suas_rede); label and unit are the same in every row.
    dic = _dictionary().drop_duplicates("field").set_index("field")
    out["label"] = out["field"].map(dic["label"]).fillna(out["field"])
    out["unit"] = out["field"].map(dic["unit"]).fillna(out["field"].map(unit_from_suffix))
    out["ibge_code"] = ibge_code7(out["locality_id"])

    order = {f: i for i, f in enumerate(fields)}
    out = out.assign(_o=out["field"].map(order)).sort_values(
        ["_o", "locality_id", "period"], kind="stable"
    )
    return out[COLUMNS].reset_index(drop=True)


def empty_result() -> pd.DataFrame:
    out = pd.DataFrame({c: pd.Series(dtype="object") for c in COLUMNS})
    out["value"] = out["value"].astype(float)
    return out


def mds_cadunico(periods=None, localities="BR", fields: Sequence[str] | None = None):
    """Cadastro Unico: registered families and people, by income bracket.

    Shortcut for :func:`mds_data` with ``mds_fields("cadunico")``.
    """
    fields = fields if fields is not None else list(mds_fields("cadunico")["field"])
    return mds_data(fields, periods=periods, localities=localities)


def mds_bolsa_familia(periods=None, localities="BR", fields: Sequence[str] | None = None):
    """Bolsa Familia programme: beneficiary families, benefits and transfers.

    Shortcut for :func:`mds_data` with ``mds_fields("bolsa_familia")``.
    """
    fields = fields if fields is not None else list(mds_fields("bolsa_familia")["field"])
    return mds_data(fields, periods=periods, localities=localities)


def mds_bpc_suas(periods=None, localities="BR", fields: Sequence[str] | None = None):
    """BPC and social assistance network (CRAS, CREAS).

    Shortcut for :func:`mds_data` with ``mds_fields("bpc_suas")``.
    """
    fields = fields if fields is not None else list(mds_fields("bpc_suas")["field"])
    return mds_data(fields, periods=periods, localities=localities)


def mds_suas_rede(periods=None, localities="BR", fields: Sequence[str] | None = None):
    """Social assistance network (CadSUAS): units and professionals by unit type.

    Shortcut for :func:`mds_data` with ``mds_fields("suas_rede")``.
    Professionals are only published from 09/2025.
    """
    fields = fields if fields is not None else list(mds_fields("suas_rede")["field"])
    return mds_data(fields, periods=periods, localities=localities)


def mds_suas_financiamento(periods=None, localities="BR", fields: Sequence[str] | None = None):
    """SUAS funding: FNAS transfers, account balances and IGD-M.

    Shortcut for :func:`mds_data` with ``mds_fields("suas_financiamento")``.
    The transfer components add up to ``suas_repasse_mun_vl_total_fundo_f``;
    the account balances do **not** add up to their general total.
    """
    fields = fields if fields is not None else list(mds_fields("suas_financiamento")["field"])
    return mds_data(fields, periods=periods, localities=localities)


def mds_pbf_condicionalidades(periods=None, localities="BR", fields: Sequence[str] | None = None):
    """Bolsa Familia conditionalities: education and health follow-up.

    Shortcut for :func:`mds_data` with ``mds_fields("pbf_condicionalidades")``:
    SICON series from 2023 on and the IGD-M follow-up rates since 2015.
    """
    fields = fields if fields is not None else list(mds_fields("pbf_condicionalidades")["field"])
    return mds_data(fields, periods=periods, localities=localities)


def mds_seguranca_alimentar(periods=None, localities="BR", fields: Sequence[str] | None = None):
    """Food and nutrition security: PAA, Fomento Rural and cisterns.

    Shortcut for :func:`mds_data` with ``mds_fields("seguranca_alimentar")``.
    Cistern counts are cumulative.
    """
    fields = fields if fields is not None else list(mds_fields("seguranca_alimentar")["field"])
    return mds_data(fields, periods=periods, localities=localities)
