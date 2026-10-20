"""Cases from the final report on 0.3.0 (same cases as test-final.R).
Parity cases are in test_paridade_casos.py."""

import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

import misocialpy as m
from misocialpy import HttpError, ResponseError, _client, data, fields, periods
from misocialpy.data import empty_result


def facet(p, n):
    return {
        "response": {"numFound": 0, "docs": []},
        "facet_counts": {"facet_fields": {"anomes_s": [p, n]}},
    }


# F1 -------------------------------------------------------------------------
def test_editing_a_periods_result_does_not_change_the_cache(monkeypatch):
    monkeypatch.setattr(periods, "mds_request", lambda q=None, label="": facet("202401", 3))
    first = m.mds_periods("bpc_ben_i")
    first.loc[0, "n_nonzero"] = 0
    first.attrs["x"] = 1
    again = m.mds_periods("bpc_ben_i")
    again.loc[0, "n_localities"] = 99
    third = m.mds_periods("bpc_ben_i")
    assert first is not again and again is not third
    assert (third.loc[0, "n_localities"], third.loc[0, "n_nonzero"]) == (3, 3)
    assert "x" not in third.attrs and "retrieved_at" in third.attrs


def test_editing_an_api_fields_result_does_not_change_the_cache(monkeypatch):
    docs = [{"id": "a", "anomes_s": "202401", "bpc_ben_i": 1}]
    monkeypatch.setattr(
        data, "mds_request", lambda q=None, label="": {"response": {"numFound": 1, "docs": docs}}
    )
    first = fields.mds_api_fields(261160)
    first.loc[0, "field"] = "changed"
    assert fields.mds_api_fields(261160)["field"].tolist() == ["bpc_ben_i"]


# F2 -------------------------------------------------------------------------
def test_flag_keeps_its_columns_on_an_empty_table():
    f = m.mds_drop_unpublished(empty_result(), action="flag")
    assert len(f) == 0
    assert {"publication_status", "publication_reason", "publication_reference"} <= set(f.columns)


# F5 -------------------------------------------------------------------------
def test_disagreeing_facets_are_read_again_then_an_error(monkeypatch):
    calls = []

    def fake(q=None, label=""):
        calls.append(1)
        return facet("202401", 2 if "-bpc_ben_i" in q["fq"][0] else 1)

    monkeypatch.setattr(periods, "mds_request", fake)
    with pytest.raises(ResponseError, match="disagree"):
        m.mds_periods("bpc_ben_i")
    assert len(calls) == 4


def test_facets_that_agree_on_the_second_read_are_used(monkeypatch):
    calls = []

    def fake(q=None, label=""):
        calls.append(1)
        nonzero = "-bpc_ben_i" in q["fq"][0]
        return facet("202401", 5 if nonzero and len(calls) <= 2 else 3)

    monkeypatch.setattr(periods, "mds_request", fake)
    assert m.mds_periods("bpc_ben_i")["n_nonzero"].tolist() == [3]
    assert len(calls) == 4


def test_documents_beyond_numfound_are_an_error(monkeypatch):
    monkeypatch.setattr(
        data,
        "mds_request",
        lambda q=None, label="": {"response": {"numFound": 0, "docs": [{"id": "a"}]}},
    )
    with pytest.raises(ResponseError, match="numFound"):
        data.fetch_all_pages({})


# F7 -------------------------------------------------------------------------
@pytest.mark.parametrize("bad", [float("nan"), float("inf"), 0, -1, True, "10"])
def test_timeout_must_be_finite_and_positive(monkeypatch, bad):
    monkeypatch.setattr(_client, "_TIMEOUT", 180.0)
    with pytest.raises(ValueError, match="finite, positive"):
        m.set_timeout(bad)
    assert _client._TIMEOUT == 180.0


# Retries against a real local server ----------------------------------------
# The `responses` mock patches the adapter and would bypass urllib3's retry
# loop; a real server exercises it.
@pytest.fixture
def fake_api(monkeypatch):
    state = {"n": 0, "fail": 0, "status": 503}

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            state["n"] += 1
            if state["n"] <= state["fail"]:
                self.send_response(state["status"])
                self.send_header("Retry-After", "0")
                self.end_headers()
                self.wfile.write(b"busy")
            else:
                body = b'{"response":{"numFound":0,"docs":[]}}'
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        def log_message(self, *args):
            pass

    srv = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    monkeypatch.setattr(_client, "MDS_BASE_URL", f"http://127.0.0.1:{srv.server_port}/")
    monkeypatch.setattr(_client, "_BACKOFF", 0)
    yield state
    srv.shutdown()


def test_a_transient_503_is_retried_and_the_next_answer_is_used(fake_api):
    fake_api["fail"] = 1
    assert _client.mds_request({"rows": 0})["response"]["numFound"] == 0
    assert fake_api["n"] == 2


def test_retries_stop_with_a_classed_http_error(fake_api):
    fake_api["fail"] = 10
    with pytest.raises(HttpError) as err:
        _client.mds_request({"rows": 0})
    assert err.value.status == 503
    # Three tries in total, as in the R package (max_tries = 3).
    assert fake_api["n"] == 3


def test_a_400_is_not_retried(fake_api):
    fake_api.update(fail=10, status=400)
    with pytest.raises(HttpError) as err:
        _client.mds_request({"rows": 0})
    assert err.value.status == 400
    assert fake_api["n"] == 1


def test_set_cache_ttl_makes_old_cached_results_expire(monkeypatch):
    from misocialpy import _cache

    calls = []
    monkeypatch.setattr(
        periods, "mds_request", lambda q=None, label="": calls.append(1) or facet("202401", 3)
    )
    m.mds_periods("bpc_ben_i")
    m.mds_periods("bpc_ben_i")
    assert len(calls) == 2
    monkeypatch.setattr(_cache, "_TTL", _cache._TTL)
    m.set_cache_ttl(0)
    m.mds_periods("bpc_ben_i")
    assert len(calls) == 4
    with pytest.raises(ValueError, match="non-negative"):
        m.set_cache_ttl(-1)
    assert _cache._TTL == 0


def test_every_field_has_a_nature_and_its_basis():
    d = m.mds_fields()
    assert set(d["nature"]) <= {
        "estoque",
        "fluxo",
        "fluxo anual",
        "acumulado",
        "taxa",
        "média",
        "índice",
    }
    assert set(d["nature_basis"]) <= {
        "medido",
        "mesmo grupo de um campo medido",
        "rótulo e unidade",
    }
    assert (d.loc[d["unit"].isin(["%", "Proporção"]), "nature"] == "taxa").all()
