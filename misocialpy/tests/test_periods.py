from datetime import date

import pytest

from misocialpy import ValidationError
from misocialpy.periods import last_months, parse_periods


def test_parse_periods_expands_years_and_keeps_months():
    assert parse_periods(2024) == [f"2024{m:02d}" for m in range(1, 13)]
    assert parse_periods(["202402", 202401]) == ["202401", "202402"]
    assert len(parse_periods([2023, 2024, 202501])) == 25


def test_parse_periods_rejects_invalid_months():
    with pytest.raises(ValidationError, match="Invalid period"):
        parse_periods(202413)
    with pytest.raises(ValidationError, match="Invalid period"):
        parse_periods("2024-01")


def test_negative_periods_count_back_from_the_current_month():
    assert last_months(3, today=date(2026, 2, 15)) == ["202512", "202601", "202602"]
    assert len(parse_periods(-6)) == 6
    assert len(parse_periods(None)) == 12
