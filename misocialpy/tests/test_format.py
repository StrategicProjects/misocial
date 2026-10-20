from misocialpy._format import chunk_vector, solr_has, solr_in, unit_from_suffix
from misocialpy.periods import parse_facet


def test_solr_in_builds_an_or_disjunction():
    assert solr_in("anomes_s", ["202401", "202402"]) == "anomes_s:(202401 OR 202402)"
    assert solr_in("sigla_uf", ["PE"]) == "sigla_uf:(PE)"


def test_solr_has_builds_an_existence_filter():
    assert solr_has("bpc_ben_i") == "bpc_ben_i:[* TO *]"


def test_chunk_vector_splits_in_groups_of_at_most_size():
    ch = chunk_vector(range(450), 200)
    assert [len(c) for c in ch] == [200, 200, 50]
    assert [x for c in ch for x in c] == list(range(450))
    assert chunk_vector([], 200) == [[]]


def test_unit_from_suffix_reads_the_dynamic_field_type():
    got = [unit_from_suffix(f) for f in ["a_i", "a_l", "a_f", "a_d", "a_s", "municipio"]]
    assert got == ["count", "count", "value", "rate", "unknown", "unknown"]


def test_parse_facet_turns_a_solr_facet_list_into_a_dataframe():
    f = parse_facet(["202401", 185, "202402", 184])
    assert list(f["period"]) == ["202401", "202402"]
    assert list(f["n"]) == [185, 184]
    assert len(parse_facet([])) == 0
