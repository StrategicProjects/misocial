"""Behaviour shared with the R package: the same cases (parity_cases.json,
copied from misocialr/tests/testthat/paridade/casos.json by
sincronizar_python.py) run in both test suites."""

import json
from datetime import date
from pathlib import Path

import pandas as pd
import pytest

import misocialpy as m
from misocialpy import DataConflictError, ResponseError, ValidationError
from misocialpy._response import check_response, dedupe_observations, doc_value
from misocialpy.localities import ibge_code7, parse_localities
from misocialpy.periods import parse_periods

CASOS = json.loads((Path(__file__).parent / "fixtures" / "parity_cases.json").read_text("utf-8"))
ERROS = {"validation": ValidationError, "response": ResponseError, "conflict": DataConflictError}


@pytest.mark.parametrize("cs", CASOS["parse_periods"], ids=lambda c: repr(c["input"]))
def test_parse_periods_behaves_as_in_r(cs):
    if "error" in cs:
        with pytest.raises(ERROS[cs["error"]]):
            parse_periods(cs["input"])
    elif "length" in cs:
        assert len(parse_periods(cs["input"])) == cs["length"]
    else:
        assert parse_periods(cs["input"]) == cs["output"]


@pytest.mark.parametrize("cs", CASOS["parse_localities"], ids=lambda c: repr(c["input"]))
def test_parse_localities_behaves_as_in_r(cs):
    if "error" in cs:
        with pytest.raises(ERROS[cs["error"]]):
            parse_localities(cs["input"])
    else:
        out = parse_localities(cs["input"])
        assert out == {"states": cs["states"], "municipalities": cs["municipalities"]}


@pytest.mark.parametrize("cs", CASOS["ibge_code7"])
def test_ibge_code7_behaves_as_in_r(cs):
    assert ibge_code7(cs["input"]) == cs["output"]


@pytest.mark.parametrize("cs", CASOS["doc_value"], ids=lambda c: repr(c["value"]))
def test_values_per_document_behave_as_in_r(cs):
    if "error" in cs:
        with pytest.raises(ERROS[cs["error"]]):
            doc_value("a_i", cs["value"])
    else:
        assert doc_value("a_i", cs["value"]) == cs["output"]


@pytest.mark.parametrize("cs", CASOS["dedupe"], ids=lambda c: repr(c["values"]))
def test_dedupe_behaves_as_in_r(cs):
    out = pd.DataFrame(
        {"locality_id": "261160", "period": "202401", "field": "a_i", "value": cs["values"]}
    ).astype({"value": float})
    if "error" in cs:
        with pytest.raises(ERROS[cs["error"]]):
            dedupe_observations(out)
    else:
        assert dedupe_observations(out)["value"].tolist() == cs["output"]


@pytest.mark.parametrize("cs", CASOS["check_response"], ids=lambda c: c["kind"])
def test_the_response_contract_behaves_as_in_r(cs):
    if cs.get("ok"):
        check_response(cs["res"], kind=cs["kind"])
    else:
        with pytest.raises(ERROS[cs["error"]]):
            check_response(cs["res"], kind=cs["kind"])


@pytest.mark.parametrize("cs", CASOS["drop_unpublished"], ids=lambda c: repr(c["period"]))
def test_mds_drop_unpublished_classifies_as_in_r(cs):
    x = pd.DataFrame({"period": cs["period"], "field": cs["field"], "value": cs["value"]})
    x["value"] = x["value"].astype(float)

    def run():
        return m.mds_drop_unpublished(
            x,
            today=date.fromisoformat(cs["today"]),
            reference=cs["reference"],
            action="flag",
        )

    if "error" in cs:
        with pytest.raises(ERROS[cs["error"]]):
            run()
    else:
        assert run()["publication_status"].tolist() == cs["status"]
