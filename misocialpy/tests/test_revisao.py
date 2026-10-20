"""Cases from the external review of 0.2.0 (same cases as test-revisao.R)."""

from datetime import date

import pandas as pd
import pytest
import responses
from conftest import cursor_server

import misocialpy as m
from misocialpy import MdsError, ValidationError, _client, data, fields, periods
from misocialpy.data import fetch_all_pages, parse_docs
from misocialpy.localities import normalize_municipality, parse_localities
from misocialpy.periods import parse_periods
from misocialpy.validation import validate_fields


@pytest.mark.parametrize("value", [[], None, [None], ["PE", ""]])
def test_an_empty_or_missing_locality_is_an_error(value):
    with pytest.raises(ValidationError, match="at least one value"):
        parse_localities(value)


def test_every_locality_is_validated_even_next_to_br():
    with pytest.raises(ValidationError, match="Invalid locality"):
        parse_localities(["BR", "Recifex"])
    with pytest.raises(ValidationError, match="Unknown state"):
        parse_localities(["BR", "99"])
    assert parse_localities(["BR", "PE", 2611606]) == {"states": [], "municipalities": []}


def test_a_7_digit_code_with_a_wrong_check_digit_is_rejected():
    with pytest.raises(ValidationError, match="(?s)Wrong check digit.*2611606"):
        parse_localities(2611600)
    with pytest.raises(ValidationError, match="Wrong check digit"):
        normalize_municipality(2611600)
    # Exceptions to the check-digit rule are accepted.
    assert parse_localities(2611533)["municipalities"] == ["261153"]
    assert parse_localities(261160)["municipalities"] == ["261160"]


@pytest.mark.parametrize(
    "value, message",
    [
        (-1.9, "whole numbers"),
        (202401.5, "whole numbers"),
        (float("inf"), "whole numbers"),
        (float("nan"), "no missing values"),
        ([202401, None], "no missing values"),
        ([], "at least one value"),
        ([-3, 202401], "used alone"),
        (0, "Invalid period"),
    ],
)
def test_periods_must_be_whole_finite_non_missing_and_non_empty(value, message):
    with pytest.raises(ValidationError, match=message):
        parse_periods(value)


def test_whole_floats_are_read_as_periods():
    assert parse_periods([2024.0, 202501])[12] == "202501"
    assert len(parse_periods(-3.0)) == 3


def test_a_text_field_is_an_error_instead_of_an_empty_result():
    docs = [{"codigo_ibge": "261160", "anomes_s": "202401", "regiao": "NORDESTE"}]
    with pytest.raises(ValidationError, match="(?s)not numeric.*NORDESTE"):
        parse_docs(docs, ["regiao"])


def test_numbers_sent_as_strings_are_still_read():
    docs = [
        {
            "codigo_ibge": "261160",
            "anomes_s": "202402",
            "valor_repassado_bolsa_familia_s": "98463694.0",
        }
    ]
    assert parse_docs(docs, ["valor_repassado_bolsa_familia_s"])["value"].tolist() == [98463694.0]


def test_identification_fields_cannot_be_requested_as_measures():
    with pytest.raises(ValidationError, match="not measures"):
        validate_fields(["bpc_ben_i", "municipio"])


def test_pagination_reads_every_page_and_fails_on_an_empty_page(monkeypatch):
    pages = [[{"id": "1"}, {"id": "2"}], [{"id": "3"}, {"id": "4"}], [{"id": "5"}]]
    seen = []
    monkeypatch.setattr(
        data, "mds_request", cursor_server(pages, on_call=lambda q: seen.append(q["cursorMark"]))
    )
    assert [d["id"] for d in fetch_all_pages({})] == ["1", "2", "3", "4", "5"]
    # Three pages, read by cursor; no extra request once numFound is reached.
    assert seen == ["*", "1", "2"]

    monkeypatch.setattr(
        data, "mds_request", lambda q=None, label="": {"response": {"numFound": 3, "docs": []}}
    )
    with pytest.raises(MdsError, match="Incomplete response"):
        fetch_all_pages({})


def test_partial_and_malformed_responses_are_errors(monkeypatch):
    monkeypatch.setattr(
        data,
        "mds_request",
        lambda q=None, label="": {
            "responseHeader": {"partialResults": True},
            "response": {"numFound": 1, "docs": [{"id": "a"}]},
        },
    )
    with pytest.raises(MdsError, match="Partial results"):
        fetch_all_pages({})
    monkeypatch.setattr(data, "mds_request", lambda q=None, label="": {"error": "x"})
    with pytest.raises(MdsError, match="Unexpected response"):
        fetch_all_pages({})


def test_mds_api_fields_returns_a_typed_empty_table_for_an_empty_locality(monkeypatch):
    monkeypatch.setattr(
        data, "mds_request", lambda q=None, label="": {"response": {"numFound": 0, "docs": []}}
    )
    with pytest.warns(UserWarning, match="no document"):
        out = fields.mds_api_fields(999999)
    assert len(out) == 0
    assert list(out.columns) == [
        "field",
        "unit",
        "storage_type",
        "in_dictionary",
        "first_period",
        "last_period",
    ]


def test_mds_api_fields_pages_through_the_whole_history(monkeypatch):
    docs = [
        {"anomes_s": "202401", "bpc_ben_i": 1},
        {"anomes_s": "202402", "bpc_ben_i": 2, "outro_l": 3},
    ]
    monkeypatch.setattr(data, "mds_request", cursor_server([[docs[0]], [docs[1]]]))
    out = fields.mds_api_fields(261160)
    assert out["field"].tolist() == ["bpc_ben_i", "outro_l"]
    assert out["first_period"].tolist() == ["202401", "202402"]
    assert out["unit"].tolist() == ["count", "count"]


@responses.activate
def test_http_errors_carry_the_solr_message_and_are_not_retried_on_400():
    responses.post(
        _client.MDS_BASE_URL,
        body='{"error":{"msg":"undefined field xyz","code":400}}',
        status=400,
        content_type="text/plain",
    )
    with pytest.raises(MdsError, match="undefined field xyz"):
        _client.mds_request({"rows": 0})
    assert len(responses.calls) == 1


def test_mds_drop_unpublished_validates_period_and_value():
    with pytest.raises(ValueError, match="YYYYMM"):
        m.mds_drop_unpublished(
            pd.DataFrame({"period": ["202401", None], "field": "a_i", "value": [1, 2]})
        )
    with pytest.raises(ValueError, match="YYYYMM"):
        m.mds_drop_unpublished(pd.DataFrame({"period": ["2024-01"], "field": "a_i", "value": [1]}))
    with pytest.raises(ValueError, match="numeric"):
        m.mds_drop_unpublished(pd.DataFrame({"period": ["202401"], "field": "a_i", "value": ["1"]}))
    with pytest.raises(ValueError, match="reference"):
        m.mds_drop_unpublished(
            pd.DataFrame({"period": ["202401"], "field": "a_i", "value": [1]}), reference="x"
        )


def test_reference_brazil_keeps_the_legitimate_zeros_of_a_selection(monkeypatch, capsys):
    # One small municipality ends in zeros, but Brazil has values up to 202509.
    x = pd.DataFrame(
        {
            "locality_id": "260005",
            "field": "cadsuas_qtd_creas_i",
            "period": ["202507", "202508", "202509", "202510"],
            "value": [1.0, 0.0, 0.0, 0.0],
        }
    )
    monkeypatch.setattr(
        periods,
        "mds_periods",
        lambda field, localities="BR", refresh=False: pd.DataFrame(
            {
                "period": ["202508", "202509", "202510"],
                "n_localities": 5570,
                "n_nonzero": [2000, 2000, 0],
            }
        ),
    )
    today = date(2025, 12, 1)
    assert m.mds_drop_unpublished(x, today=today)["period"].tolist() == ["202507"]
    m.set_verbose(True)
    br = m.mds_drop_unpublished(x, today=today, reference="brazil")
    assert br["period"].tolist() == ["202507", "202508", "202509"]
    assert "published in Brazil" in capsys.readouterr().err


def test_mds_data_records_the_time_of_the_request(monkeypatch):
    monkeypatch.setattr(data, "validate_fields", lambda f: None)
    monkeypatch.setattr(
        data,
        "fetch_all_pages",
        lambda q, label="": [{"codigo_ibge": "261160", "anomes_s": "202401", "bpc_ben_i": 1}],
    )
    out = m.mds_data("bpc_ben_i", periods=202401, localities=2611606)
    assert out.attrs["retrieved_at"].endswith("+00:00")


def test_the_timeout_can_be_set(monkeypatch):
    seen = {}

    class FakeSession:
        def post(self, url, data=None, timeout=None):
            seen["timeout"] = timeout

            class R:
                status_code = 200

                def json(self):
                    return {"response": {"numFound": 0, "docs": []}}

            return R()

    monkeypatch.setattr(_client, "_session", lambda: FakeSession())
    monkeypatch.setattr(_client, "_TIMEOUT", 180.0)
    m.set_timeout(7)
    _client.mds_request({"rows": 0})
    assert seen["timeout"] == 7.0
    with pytest.raises(ValueError, match="positive"):
        m.set_timeout(0)
