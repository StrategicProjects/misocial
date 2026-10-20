import pytest

from misocialpy import ValidationError, mds_fields, mds_themes
from misocialpy.data import COLUMNS, build_query_plan, parse_docs
from misocialpy.fields import _dictionary


def test_the_dictionary_is_consistent():
    d = _dictionary()
    assert not d.duplicated(["theme", "field"]).any()
    # A field repeated across themes keeps the same label and unit.
    assert not d.drop_duplicates(["field", "label", "unit"])["field"].duplicated().any()
    assert set(d["theme"]) == set(mds_themes()["theme"])
    assert d["field"].str.contains(r"_[ifdl]$").all()
    assert (d["label"] != "").all()


def test_mds_fields_filters_by_theme_and_validates_it():
    bpc = mds_fields("bpc_suas")
    assert (bpc["theme"] == "bpc_suas").all()
    assert "cadsuas_qtd_cras_i" in set(bpc["field"])
    assert len(mds_fields()) == len(_dictionary())
    with pytest.raises(ValidationError, match="Unknown theme"):
        mds_fields("saude")


def test_mds_themes_counts_fields_per_theme():
    assert mds_themes()["n_fields"].sum() == len(_dictionary())


def test_build_query_plan_splits_long_municipality_lists():
    codes = [f"26{i:04d}" for i in range(1, 451)]
    plan = build_query_plan(
        ["bpc_ben_i"], ["202401", "202402"], {"states": ["PB"], "municipalities": codes}
    )
    assert len(plan) == 4
    assert plan[0]["fq"] == ["anomes_s:(202401 OR 202402)", "sigla_uf:(PB)"]
    assert plan[1]["fq"][1].startswith("codigo_ibge:(260001 OR")
    assert plan[0]["fl"] == "id,codigo_ibge,municipio,sigla_uf,anomes_s,bpc_ben_i"


def test_build_query_plan_without_localities_has_a_single_request():
    plan = build_query_plan(["bpc_ben_i"], ["202401"], {"states": [], "municipalities": []})
    assert len(plan) == 1
    assert plan[0]["fq"] == ["anomes_s:(202401)"]


def test_parse_docs_flattens_sparse_documents():
    base = {"codigo_ibge": "261160", "municipio": "RECIFE", "sigla_uf": "PE"}
    docs = [
        {**base, "anomes_s": "202402", "bpc_ben_i": 90187, "cadsuas_qtd_cras_i": 16},
        {**base, "anomes_s": "202401", "bpc_ben_i": 90000},
        {**base, "anomes_s": "202401", "outro_campo_i": 1},
    ]
    out = parse_docs(docs, ["bpc_ben_i", "cadsuas_qtd_cras_i", "outro_campo_i"])
    assert list(out.columns) == COLUMNS
    assert len(out) == 4
    assert list(out["field"]) == ["bpc_ben_i", "bpc_ben_i", "cadsuas_qtd_cras_i", "outro_campo_i"]
    assert list(out["period"][:2]) == ["202401", "202402"]
    assert set(out["ibge_code"]) == {"2611606"}
    assert out["value"].dtype == float
    # Fields outside the dictionary fall back to the technical name and suffix.
    assert out["label"].iloc[3] == "outro_campo_i"
    assert out["unit"].iloc[3] == "count"
    assert out["label"].iloc[0] == "Beneficiários do BPC"


def test_parse_docs_returns_a_typed_empty_dataframe():
    out = parse_docs([], ["bpc_ben_i"])
    assert len(out) == 0
    assert list(out.columns) == COLUMNS
    assert out["value"].dtype == float


def test_every_theme_shortcut_requests_the_curated_fields(monkeypatch):
    import misocialpy as m
    from misocialpy import data

    shortcuts = {
        "cadunico": m.mds_cadunico,
        "bolsa_familia": m.mds_bolsa_familia,
        "bpc_suas": m.mds_bpc_suas,
        "suas_rede": m.mds_suas_rede,
        "suas_financiamento": m.mds_suas_financiamento,
        "pbf_condicionalidades": m.mds_pbf_condicionalidades,
        "seguranca_alimentar": m.mds_seguranca_alimentar,
    }
    assert set(shortcuts) == set(mds_themes()["theme"])
    monkeypatch.setattr(data, "mds_data", lambda fields, **kw: fields)
    for theme, fn in shortcuts.items():
        assert fn(periods=202401) == list(mds_fields(theme)["field"])


def test_a_field_in_two_themes_produces_a_single_row_per_value():
    docs = [
        {
            "codigo_ibge": "261160",
            "municipio": "RECIFE",
            "sigla_uf": "PE",
            "anomes_s": "202609",
            "cadsuas_qtd_cras_i": 18,
        }
    ]
    out = parse_docs(docs, ["cadsuas_qtd_cras_i"])
    assert len(out) == 1
    assert out["label"].tolist() == ["Unidades CRAS"]
