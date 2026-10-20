from datetime import date

import pandas as pd
import pytest

from misocialpy import mds_drop_unpublished


def make_series(field="bpc_ben_i", offset=0):
    periods = ["202505", "202506", "202507", "202508", "202509", "202510"]
    return pd.DataFrame(
        {
            "locality_id": ["261160"] * 6 + ["260790"] * 6,
            "period": periods * 2,
            "field": field,
            "value": [v + (offset if v else 0) for v in [10, 0, 12, 13, 0, 0, 20, 0, 22, 23, 0, 0]],
        }
    )


def test_trailing_all_zero_months_are_dropped_middle_zeros_kept():
    out = mds_drop_unpublished(make_series(), today=date(2025, 12, 1))
    assert sorted(out["period"].unique()) == ["202505", "202506", "202507", "202508"]
    # 202506 is zero everywhere but followed by values: a real zero.
    assert (out["period"] == "202506").sum() == 2


def test_future_months_are_dropped():
    out = mds_drop_unpublished(make_series(), today=date(2025, 7, 10))
    assert out["period"].max() == "202507"


def test_a_trailing_zero_in_one_locality_only_is_kept():
    x = make_series()
    x.loc[(x["locality_id"] == "260790") & (x["period"] == "202509"), "value"] = 5
    out = mds_drop_unpublished(x, today=date(2025, 12, 1))
    assert out["period"].max() == "202509"
    assert (out["period"] == "202509").sum() == 2


def test_a_field_without_any_non_zero_value_is_dropped_entirely():
    x = make_series()
    x["value"] = 0
    assert len(mds_drop_unpublished(x, today=date(2025, 12, 1))) == 0


def test_fields_are_handled_independently():
    y = make_series("bpc_val_f")
    y["value"] = y["value"] + 1
    x = pd.concat([make_series(), y])
    out = mds_drop_unpublished(x, today=date(2025, 12, 1))
    assert out.loc[out["field"] == "bpc_val_f", "period"].max() == "202510"
    assert out.loc[out["field"] == "bpc_ben_i", "period"].max() == "202508"


def test_reports_and_validates_input(capsys):
    import misocialpy

    misocialpy.set_verbose(True)
    mds_drop_unpublished(make_series(), today=date(2025, 12, 1))
    assert "trailing all-zero" in capsys.readouterr().err
    with pytest.raises(ValueError, match="must have columns"):
        mds_drop_unpublished(pd.DataFrame({"x": [1]}))
