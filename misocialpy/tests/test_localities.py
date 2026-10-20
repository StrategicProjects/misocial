from datetime import date

import pytest

from misocialpy import ValidationError, ibge_code7
from misocialpy.localities import (
    IBGE_DV_EXCEPTIONS,
    localities_period,
    normalize_municipality,
    parse_localities,
    states_to_abbr,
)


def test_ibge_code7_applies_the_check_digit_rule():
    assert ibge_code7([261160, "260790", "530010"]) == ["2611606", "2607901", "5300108"]
    assert ibge_code7(261160) == "2611606"


def test_ibge_code7_uses_the_exception_table():
    assert ibge_code7(["261153", "220191", "520396"]) == ["2611533", "2201919", "5203962"]
    assert len(IBGE_DV_EXCEPTIONS) == 9


def test_ibge_code7_returns_none_for_malformed_input():
    assert ibge_code7(["26116", "2611606", None]) == [None, None, None]


def test_normalize_municipality_accepts_6_or_7_digits():
    assert normalize_municipality(2611606) == "261160"
    assert normalize_municipality("261160") == "261160"
    with pytest.raises(ValidationError, match="6- or 7-digit"):
        normalize_municipality("PE")


def test_states_to_abbr_maps_codes_and_abbreviations():
    assert states_to_abbr(["pe", 26, "35"]) == ["PE", "PE", "SP"]
    with pytest.raises(ValidationError, match="Unknown state"):
        states_to_abbr(["XX"])


def test_parse_localities_handles_every_accepted_form():
    assert parse_localities("BR") == {"states": [], "municipalities": []}
    mixed = parse_localities(["PE", 25, 2611606, "260790", "2611606"])
    assert mixed["states"] == ["PE", "PB"]
    assert mixed["municipalities"] == ["261160", "260790"]
    with pytest.raises(ValidationError, match="Invalid locality"):
        parse_localities("Recife")
    with pytest.raises(ValidationError, match="at least one value"):
        parse_localities(None)


def test_localities_period_is_december_of_the_previous_year():
    assert localities_period(date(2026, 10, 19)) == "202512"
