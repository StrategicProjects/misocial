"""The curated dictionary must stay identical to the R package's."""

from pathlib import Path

import pytest

DATA = Path(__file__).parents[1] / "src" / "misocialpy" / "data"
R_EXTDATA = Path(__file__).parents[2] / "misocialr" / "inst" / "extdata"


@pytest.mark.parametrize("name", ["dictionary.csv", "themes.csv"])
def test_csv_matches_r_package(name):
    r_file = R_EXTDATA / name
    if not r_file.exists():
        pytest.skip("R sibling package not found next to this one")
    assert (DATA / name).read_bytes() == r_file.read_bytes()
