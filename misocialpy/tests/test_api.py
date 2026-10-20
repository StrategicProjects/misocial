"""Integration tests against responses recorded from the live API.

The fixtures are the bodies recorded by the R package with httptest2, so the
two packages are checked against the same data.
"""

import pytest

import misocialpy as m


def test_mds_data_fetches_and_tidies_a_small_query(fake_api):
    out = m.mds_data(
        ["qtd_familias_beneficiarias_bolsa_familia_i", "bpc_ben_i"],
        periods=[202402, 202509],
        localities=[2611606, 2607901],
    )
    assert len(out) == 8
    assert set(out["ibge_code"]) == {"2611606", "2607901"}
    recife = out[
        (out["locality_id"] == "261160")
        & (out["period"] == "202402")
        & (out["field"] == "qtd_familias_beneficiarias_bolsa_familia_i")
    ]
    assert recife["value"].tolist() == [146737.0]
    assert recife["unit"].tolist() == ["Famílias"]
    assert fake_api[0]["sort"] == "id asc"


def test_theme_shortcuts_request_their_curated_fields(fake_api):
    out = m.mds_bpc_suas(periods=202509, localities=2611606)
    assert set(out["field"]) == set(m.mds_fields("bpc_suas")["field"])
    assert out.loc[out["field"] == "cadsuas_qtd_cras_i", "value"].tolist() == [16.0]


def test_mds_periods_separates_published_values_from_zeros(fake_api):
    p = m.mds_periods("bpc_ben_i", localities="PE")
    assert list(p.columns) == ["period", "n_localities", "n_nonzero"]
    assert p["period"].iloc[0] == "200301"
    assert (p["n_localities"] == 185).all()
    # The recording has months already listed but still all zero.
    assert (p["n_nonzero"] == 0).any()
    n = len(fake_api)
    # Second call comes from the cache (no HTTP)
    assert m.mds_periods("bpc_ben_i", localities="PE").equals(p)
    assert len(fake_api) == n


def test_mds_localities_lists_municipalities_with_7_digit_codes(fake_api):
    locs = m.mds_localities()
    assert len(locs) == 5571
    assert locs["ibge_code"].notna().all()
    assert len(m.mds_localities("PE")) == 185
    assert locs.loc[locs["ibge_code"] == "2611606", "locality_name"].tolist() == ["RECIFE"]


def test_unknown_fields_are_rejected_before_any_data_request(fake_api):
    with pytest.raises(m.ValidationError, match="not found"):
        m.mds_data("campo_inexistente_i", periods=202401, localities="PE")
    assert len(fake_api) == 1


@pytest.mark.live
def test_live_recife_bolsa_familia():
    out = m.mds_data(
        "qtd_familias_beneficiarias_bolsa_familia_i", periods=202402, localities=2611606
    )
    assert out["value"].tolist() == [146737.0]
