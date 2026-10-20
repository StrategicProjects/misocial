"""Shared fixtures.

``fake_api`` replays responses recorded from the live API. The JSON files in
``tests/fixtures/`` are the same bodies the R package (misocialr) records with
httptest2, so both packages are tested against identical data.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

import misocialpy
from misocialpy import _cache, data, fields, localities, periods, validation

FIXTURES = Path(__file__).parent / "fixtures"

# Recorded filter queries -> fixture file
ROUTES = {
    ("anomes_s:(202402 OR 202509)", "codigo_ibge:(261160 OR 260790)"): "data_recife_jaboatao.json",
    ("anomes_s:(202509)", "codigo_ibge:(261160)"): "bpc_suas_recife_202509.json",
    ("bpc_ben_i:[* TO *]", "sigla_uf:(PE)"): "periods_bpc_pe.json",
    ("bpc_ben_i:[* TO *] AND -bpc_ben_i:0", "sigla_uf:(PE)"): "periods_bpc_pe_nonzero.json",
    ("anomes_s:202512",): "localities_202512.json",
    ("campo_inexistente_i:[* TO *]",): "field_check_missing.json",
}


def cursor_server(pages, totals=None, on_call=None):
    """Serve pages by cursorMark, as the MI Social Solr does."""
    totals = totals or [sum(len(p) for p in pages)] * len(pages)

    def fake(q=None, label=""):
        i = 0 if q["cursorMark"] == "*" else int(q["cursorMark"])
        if on_call:
            on_call(q)
        return {
            "response": {"numFound": totals[i], "docs": pages[i]},
            "nextCursorMark": str(min(i + 1, len(pages) - 1)),
        }

    return fake


def load_fixture(name: str):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def pytest_configure(config):
    # Registered here too, so the suite behaves the same when run outside the
    # project (against an installed wheel, without pyproject.toml).
    config.addinivalue_line("markers", "live: hits the real MI Social API (run with -m live)")


def pytest_collection_modifyitems(config, items):
    # Without `-m`, the live test is skipped, as `addopts` does in pyproject.
    if config.getoption("-m"):
        return
    skip = pytest.mark.skip(reason="live test; run with -m live")
    for item in items:
        if "live" in item.keywords:
            item.add_marker(skip)


@pytest.fixture(autouse=True)
def _quiet_and_clean():
    misocialpy.set_verbose(False)
    _cache._CACHE.clear()
    yield
    _cache._CACHE.clear()


@pytest.fixture
def fake_api(monkeypatch):
    """Replace every module's ``mds_request`` with the recorded responses.

    Returns the list of queries made, so tests can assert on them. An
    unrecorded query fails the test, as httptest2 does in R.
    """
    calls = []

    def fake_request(query=None, label="data"):
        query = dict(query or {})
        calls.append(query)
        fq = query.get("fq")
        key = tuple([fq] if isinstance(fq, str) else fq)
        if key not in ROUTES:
            raise AssertionError(f"Unexpected request: {query}")
        return load_fixture(ROUTES[key])

    for mod in (data, fields, localities, periods, validation):
        if hasattr(mod, "mds_request"):
            monkeypatch.setattr(mod, "mds_request", fake_request)
    monkeypatch.setattr(localities, "localities_period", lambda today=None: "202512")
    return calls
