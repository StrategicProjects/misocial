"""Cases from the deep review of 0.2.1 (same cases as test-profunda.R)."""

from datetime import date

import pandas as pd
import pytest
import responses
from conftest import cursor_server

import misocialpy as m
from misocialpy import (
    DataConflictError,
    HttpError,
    MdsError,
    ResponseError,
    ValidationError,
    _cache,
    _client,
    data,
    periods,
)
from misocialpy._format import storage_from_suffix, unit_from_suffix
from misocialpy._response import check_response, dedupe_observations
from misocialpy.data import build_query_plan, fetch_all_pages, parse_docs
from misocialpy.localities import ibge_code7
from misocialpy.validation import field_exists


def facet(*pairs):
    return {
        "responseHeader": {"status": 0},
        "response": {"numFound": 0, "docs": []},
        "facet_counts": {"facet_fields": {"anomes_s": list(pairs)}},
    }


# B1 -------------------------------------------------------------------------
def test_a_partial_or_facet_less_answer_is_not_cached(monkeypatch):
    monkeypatch.setattr(
        periods,
        "mds_request",
        lambda q=None, label="": {
            "responseHeader": {"partialResults": True},
            "response": {"numFound": 0, "docs": []},
        },
    )
    with pytest.raises(ResponseError, match="Partial"):
        m.mds_periods("bpc_ben_i")
    monkeypatch.setattr(
        periods, "mds_request", lambda q=None, label="": {"response": {"numFound": 0, "docs": []}}
    )
    with pytest.raises(ResponseError, match="facet_counts"):
        m.mds_periods("bpc_ben_i")
    assert not [k for k in _cache._CACHE if k.startswith("periods")]


def test_an_empty_facet_is_valid_and_cached(monkeypatch):
    monkeypatch.setattr(periods, "mds_request", lambda q=None, label="": facet())
    assert len(m.mds_periods("bpc_ben_i")) == 0
    assert [k for k in _cache._CACHE if k.startswith("periods")]


# B2 -------------------------------------------------------------------------
RECIFE = {"id": "a", "codigo_ibge": "261160", "municipio": "RECIFE", "sigla_uf": "PE"}
OLINDA = {"id": "b", "codigo_ibge": "260960", "municipio": "OLINDA", "sigla_uf": "PE"}


def test_an_incomplete_municipality_list_is_rejected_and_not_cached(monkeypatch):
    monkeypatch.setattr(
        data,
        "mds_request",
        lambda q=None, label="": {
            "responseHeader": {"partialResults": True},
            "response": {"numFound": 5571, "docs": [RECIFE]},
        },
    )
    with pytest.raises(ResponseError):
        m.mds_localities()
    assert not [k for k in _cache._CACHE if k.startswith("localities")]


def test_the_municipality_list_is_paged_until_numfound(monkeypatch):
    monkeypatch.setattr(data, "mds_request", cursor_server([[RECIFE], [OLINDA]]))
    locs = m.mds_localities(period="202512")
    assert locs["ibge_code"].tolist() == ["2609600", "2611606"]
    assert locs.attrs["period"] == "202512"
    assert "retrieved_at" in locs.attrs


# B3 -------------------------------------------------------------------------
def test_a_national_reference_never_removes_a_non_zero_value(monkeypatch):
    calls = []

    def fake(field, localities="BR", refresh=False):
        calls.append(refresh)
        return pd.DataFrame({"period": ["202401"], "n_localities": [1], "n_nonzero": [0]})

    monkeypatch.setattr(periods, "mds_periods", fake)
    x = pd.DataFrame({"period": ["202401"], "field": ["bpc_ben_i"], "value": [90000.0]})
    with pytest.warns(UserWarning, match="contradicts"):
        out = m.mds_drop_unpublished(x, today=date(2025, 1, 1), reference="brazil")
    assert out["value"].tolist() == [90000.0]
    assert calls == [False, True]


def test_a_refreshed_reference_that_agrees_with_the_data_is_used(monkeypatch):
    def fake(field, localities="BR", refresh=False):
        last = "202402" if refresh else "202312"
        return pd.DataFrame({"period": [last], "n_localities": [1], "n_nonzero": [1]})

    monkeypatch.setattr(periods, "mds_periods", fake)
    x = pd.DataFrame({"period": ["202401", "202402"], "field": "bpc_ben_i", "value": [5.0, 0.0]})
    out = m.mds_drop_unpublished(x, today=date(2025, 1, 1), reference="brazil")
    assert out["period"].tolist() == ["202401", "202402"]


# B4 -------------------------------------------------------------------------
def test_conflicting_values_for_the_same_key_are_an_error():
    out = pd.DataFrame(
        {"locality_id": "261160", "period": "202401", "field": "a_i", "value": [10.0, 20.0]}
    )
    with pytest.raises(DataConflictError):
        dedupe_observations(out)
    same = out.assign(value=[10.0, 10.0])
    assert len(dedupe_observations(same)) == 1


def test_documents_without_municipality_or_month_are_an_error():
    docs = [{"municipio": "RECIFE", "anomes_s": "202401", "a_i": 1}]
    with pytest.raises(ResponseError, match="codigo_ibge"):
        parse_docs(docs, ["a_i"])
    with pytest.raises(ResponseError, match="anomes_s"):
        parse_docs([{"codigo_ibge": "261160", "anomes_s": "2024", "a_i": 1}], ["a_i"])


def test_a_municipality_inside_a_requested_state_is_not_requested_twice():
    plan = build_query_plan(
        ["a_i"], ["202401"], {"states": ["PE"], "municipalities": ["261160", "355030"]}
    )
    assert len(plan) == 2
    assert plan[1]["fq"][1] == "codigo_ibge:(355030)"
    assert plan[0]["fl"].startswith("id,")


# B5 -------------------------------------------------------------------------
def test_a_list_or_several_values_in_one_document_is_an_error():
    docs = [
        {"codigo_ibge": "261160", "anomes_s": "202401", "a_i": []},
        {"codigo_ibge": "260960", "anomes_s": "202401", "a_i": [10, 20]},
    ]
    with pytest.raises(ResponseError, match="single value"):
        parse_docs(docs, ["a_i"])


# B6 -------------------------------------------------------------------------
@pytest.mark.parametrize("p", ["202400", "202413"])
def test_periods_in_the_cleaning_step_must_be_real_months(p):
    with pytest.raises(ValidationError, match="01 to 12"):
        m.mds_drop_unpublished(pd.DataFrame({"period": [p], "field": "a_i", "value": [1.0]}))


def test_categorical_and_numeric_periods_are_read_by_their_values():
    cat = pd.DataFrame(
        {"period": pd.Categorical(["202401", "202601"]), "field": "a_i", "value": [1.0, 1.0]}
    )
    out = m.mds_drop_unpublished(cat, today=date(2025, 1, 1))
    assert [str(p) for p in out["period"]] == ["202401"]
    num = pd.DataFrame({"period": [202401, 202601], "field": "a_i", "value": [1.0, 1.0]})
    assert m.mds_drop_unpublished(num, today=date(2025, 1, 1))["period"].tolist() == [202401]


# B7 -------------------------------------------------------------------------
def test_field_today_and_value_are_validated():
    with pytest.raises(ValidationError, match="field"):
        m.mds_drop_unpublished(
            pd.DataFrame({"period": ["202401"], "field": [None], "value": [1.0]})
        )
    y = pd.DataFrame({"period": ["202401"], "field": "a_i", "value": [1.0]})
    with pytest.raises(ValidationError, match="single date"):
        m.mds_drop_unpublished(y, today="2025-01-01")
    with pytest.raises(ValidationError, match="infinite"):
        m.mds_drop_unpublished(y.assign(value=[float("inf")]))


def test_a_missing_value_is_kept_and_flagged():
    x = pd.DataFrame({"period": ["202401", "202402"], "field": "a_i", "value": [5.0, None]})
    assert m.mds_drop_unpublished(x, today=date(2025, 1, 1))["period"].tolist() == [
        "202401",
        "202402",
    ]
    f = m.mds_drop_unpublished(x, today=date(2025, 1, 1), action="flag")
    assert f["publication_status"].tolist() == ["published", "missing"]


# M2 -------------------------------------------------------------------------
def test_flag_classifies_every_row_without_removing_any():
    x = pd.DataFrame(
        {
            "period": ["202506", "202507", "202508", "202601"],
            "field": "bpc_ben_i",
            "value": [10.0, 12.0, 0.0, 0.0],
        }
    )
    f = m.mds_drop_unpublished(x, today=date(2025, 12, 1), action="flag")
    assert len(f) == 4
    assert f["publication_status"].tolist() == ["published", "published", "unpublished", "future"]
    assert "202507" in f["publication_reason"].iloc[2]
    assert set(f["publication_reference"]) == {"selection"}
    with pytest.raises(ValidationError, match="action"):
        m.mds_drop_unpublished(x, action="x")


# B8 -------------------------------------------------------------------------
@pytest.mark.parametrize(
    "res, kind, message",
    [
        ({"response": {"numFound": 0}}, "docs", "docs"),
        ({"response": {"numFound": -1, "docs": []}}, "docs", "numFound"),
        ({"response": {"numFound": 1.5, "docs": []}}, "docs", "numFound"),
        ({"response": {"numFound": 1, "docs": [1]}}, "docs", "list of documents"),
        ("x", "docs", "response"),
        (
            {"responseHeader": {"status": 500}, "response": {"numFound": 0, "docs": []}},
            "docs",
            "status",
        ),
        ({"response": {"numFound": 0}}, "facet", "facet_counts"),
    ],
)
def test_check_response_enforces_the_contract(res, kind, message):
    with pytest.raises(ResponseError, match=message):
        check_response(res, kind=kind)


def test_check_response_accepts_valid_answers():
    check_response({"response": {"numFound": 0}}, kind="count")
    check_response(facet("202401", 3), kind="facet")


# M1 -------------------------------------------------------------------------
def test_refresh_asks_again_and_equivalent_selections_share_the_cache(monkeypatch):
    calls = []
    monkeypatch.setattr(
        periods, "mds_request", lambda q=None, label="": calls.append(1) or facet("202401", 3)
    )
    m.mds_periods("bpc_ben_i", localities=["PE", "PB"])
    m.mds_periods("bpc_ben_i", localities=["PB", "PE"])
    assert len(calls) == 2
    m.mds_periods("bpc_ben_i", localities=["PB", "PE"], refresh=True)
    assert len(calls) == 4


# M4 -------------------------------------------------------------------------
def test_large_selections_are_counted_in_disjoint_blocks_and_summed(monkeypatch):
    import re

    from misocialpy import localities

    seen = []
    monkeypatch.setattr(localities, "check_dv", lambda codes: None)
    monkeypatch.setattr(
        periods,
        "mds_request",
        lambda q=None, label="": seen.append(q["fq"][1]) or facet("202401", 2),
    )
    p = m.mds_periods("bpc_ben_i", localities=[f"26{i:04d}" for i in range(1, 451)])
    assert len(seen) == 6
    n_codes = [len(re.findall(r"[0-9]{6}", s)) for s in seen]
    assert max(n_codes) <= 200 and sum(n_codes) == 900
    assert p["n_localities"].tolist() == [6]


# M5 -------------------------------------------------------------------------
def test_a_total_that_changes_while_paging_is_an_error(monkeypatch):
    monkeypatch.setattr(
        data,
        "mds_request",
        cursor_server([[{"id": "a"}, {"id": "b"}], [{"id": "c"}]], totals=[3, 4]),
    )
    with pytest.raises(ResponseError, match="changed while it was being read"):
        fetch_all_pages({})


def test_a_document_read_twice_is_an_error(monkeypatch):
    monkeypatch.setattr(data, "mds_request", cursor_server([[{"id": "a"}], [{"id": "a"}]]))
    with pytest.raises(ResponseError, match="same document twice"):
        fetch_all_pages({})


def test_a_cursor_that_stops_before_numfound_is_an_error(monkeypatch):
    monkeypatch.setattr(
        data,
        "mds_request",
        lambda q=None, label="": {
            "response": {"numFound": 3, "docs": [{"id": "a"}]},
            "nextCursorMark": q["cursorMark"],
        },
    )
    with pytest.raises(ResponseError, match="Incomplete response"):
        fetch_all_pages({})


def test_cursormark_is_sent_with_a_sort_on_the_unique_key(monkeypatch):
    seen = {}

    def fake(q=None, label=""):
        seen.update(q)
        return {"response": {"numFound": 0, "docs": []}}

    monkeypatch.setattr(data, "mds_request", fake)
    fetch_all_pages({"fq": "x"})
    assert seen["cursorMark"] == "*" and seen["sort"] == "id asc" and "start" not in seen


# M6 -------------------------------------------------------------------------
def test_ibge_code7_gives_the_same_result_for_repeated_codes():
    assert (
        ibge_code7(["261160", "261153", None, "12345"] * 1000)
        == ["2611606", "2611533", None, None] * 1000
    )


# M7 -------------------------------------------------------------------------
def test_local_checks_run_even_with_validate_false():
    with pytest.raises(ValidationError, match="non-empty list"):
        m.mds_data([1], validate=False)
    with pytest.raises(ValidationError, match="Invalid field name"):
        m.mds_data("a b", validate=False)
    with pytest.raises(ValidationError, match="True or False"):
        m.mds_data("bpc_ben_i", validate=None)
    with pytest.raises(ValidationError, match="not measures"):
        m.mds_data("id", validate=False)


# M8 -------------------------------------------------------------------------
@responses.activate
def test_http_errors_are_classed_and_keep_the_status():
    responses.post(
        _client.MDS_BASE_URL, body='{"error":{"msg":"undefined field x_i","code":400}}', status=400
    )
    with pytest.raises(HttpError) as err:
        _client.mds_request({"rows": 0})
    assert err.value.status == 400
    assert isinstance(err.value, MdsError)
    assert field_exists("x_i") is False


@responses.activate
def test_invalid_json_is_a_response_error():
    responses.post(_client.MDS_BASE_URL, body="<html>", status=200)
    with pytest.raises(ResponseError, match="not valid JSON"):
        _client.mds_request({"rows": 0})


def test_the_user_agent_carries_the_package_version():
    assert _client._user_agent().startswith(f"misocialpy/{m.__version__}")


def test_connection_failures_are_retried():
    retry = _client._session().get_adapter("https://").max_retries
    assert retry.connect == 2 and retry.total == 2


def test_every_error_inherits_from_mds_error():
    for cls in (HttpError, ResponseError, DataConflictError, ValidationError):
        assert issubclass(cls, MdsError)
    assert issubclass(ValidationError, ValueError)


# M9 -------------------------------------------------------------------------
def test_a_requested_municipality_without_documents_raises_a_warning(monkeypatch):
    monkeypatch.setattr(data, "fetch_all_pages", lambda q, label="": [])
    with pytest.warns(UserWarning, match="1100015"):
        m.mds_data("bpc_ben_i", periods=202401, localities=1100015)


# M3 -------------------------------------------------------------------------
def test_storage_type_and_unit_are_kept_apart():
    assert [unit_from_suffix(f) for f in ["a_s", "a_i", "regiao"]] == [
        "unknown",
        "count",
        "unknown",
    ]
    assert [storage_from_suffix(f) for f in ["a_s", "a_i", "a_l", "x"]] == [
        "string",
        "integer",
        "long",
        "untyped",
    ]
    assert "storage_type" in m.mds_fields().columns
