"""Curated field dictionary and the live field list.

The dictionary and the theme table are read from ``data/*.csv`` (UTF-8),
copied verbatim from the R package (``misocialr/inst/extdata``).

The API publishes no data dictionary: every curated field was checked to have
values in the live API and the labels are a Portuguese reading of each
technical name. ``pbf_qtd_familias_benef_i`` is *not* the headline Bolsa
Familia count (Recife, 02/2024: 9,847 against 146,737 in
``qtd_familias_beneficiarias_bolsa_familia_i``) and is left out.
"""

from __future__ import annotations

import warnings
from collections.abc import Sequence
from importlib import resources

import pandas as pd

from . import _cache
from ._format import ID_FIELDS, storage_from_suffix, unit_from_suffix
from .validation import validate_theme


def _read_data(name: str) -> pd.DataFrame:
    path = resources.files("misocialpy").joinpath("data", name)
    with path.open("r", encoding="utf-8") as fh:
        return pd.read_csv(fh, dtype=str, keep_default_na=False)


def _dictionary() -> pd.DataFrame:
    if "dictionary" not in _cache._CACHE:
        _cache._CACHE["dictionary"] = _read_data("dictionary.csv")
    return _cache._CACHE["dictionary"]


def _themes() -> pd.DataFrame:
    if "themes" not in _cache._CACHE:
        _cache._CACHE["themes"] = _read_data("themes.csv")
    return _cache._CACHE["themes"]


def mds_themes() -> pd.DataFrame:
    """List the themes covered by the package.

    Each theme groups a curated set of fields (see :func:`mds_fields`) and has
    a shortcut function: :func:`mds_cadunico`, :func:`mds_bolsa_familia` and
    :func:`mds_bpc_suas`.

    Returns a DataFrame with columns ``theme``, ``name``, ``description`` and
    ``n_fields``.
    """
    th = _themes().copy()
    counts = _dictionary()["theme"].value_counts()
    th["n_fields"] = th["theme"].map(counts).fillna(0).astype(int)
    return th


def mds_fields(theme: str | Sequence[str] | None = None) -> pd.DataFrame:
    """List curated fields: technical name, Portuguese label, unit and storage type.

    The API has no data dictionary. Labels are a reading of the technical
    names, checked against the published values; units are what is counted.
    ``storage_type`` is the Solr type given by the suffix (``_i`` integer,
    ``_l`` long, ``_f`` float, ``_d`` double, ``_s`` string) and says nothing
    about the unit.

    ``nature`` says how a field may be aggregated: ``estoque`` (count at the
    month: sum across municipalities, not months), ``fluxo`` (amount in the
    month: sum across both), ``fluxo anual`` (one value a year, in December),
    ``acumulado`` (running total: sum across municipalities, not months) and
    ``taxa``, ``média``, ``índice`` (do not sum). ``nature_basis`` is
    ``medido``, ``mesmo grupo de um campo medido`` or ``rótulo e unidade``.

    Parameters
    ----------
    theme:
        Optional theme id (see :func:`mds_themes`) or list of ids. ``None``
        returns all themes.

    Returns a DataFrame with columns ``theme``, ``field``, ``label``, ``unit``,
    ``nature``, ``nature_basis`` and ``storage_type``.
    """
    d = _dictionary()
    if theme is not None:
        themes = [theme] if isinstance(theme, str) else list(theme)
        validate_theme(themes)
        d = d[d["theme"].isin(themes)]
    d = d.reset_index(drop=True).copy()
    d["storage_type"] = d["field"].map(storage_from_suffix)
    return d


def mds_api_fields(locality: int | str = 261160, refresh: bool = False) -> pd.DataFrame:
    """List the fields published for one municipality.

    Fetches the full documents of one municipality over all months (paging
    through the whole history) and returns the union of the field names found,
    with the first and last period in which each appears. MI Social documents
    are sparse (a field only exists in the months it was published), which is
    why the whole history is scanned.

    This is the catalogue of **one** municipality, not of the whole API: fields
    that exist only elsewhere (a regional CREAS, for instance) do not appear.
    Cached for the session (``refresh=True`` asks again).

    Returns a DataFrame with columns ``field``, ``unit`` (``"unknown"`` when the
    suffix does not say), ``storage_type``, ``in_dictionary``, ``first_period``
    and ``last_period``; empty, with a warning, when the API has no document
    for the municipality.
    """
    from .data import fetch_all_pages
    from .localities import normalize_municipality
    from .validation import check_flag

    check_flag(refresh, "refresh")
    code = normalize_municipality(locality)
    key = f"api_fields_{code}"
    cached = _cache.cache_get(key, refresh)
    if cached is not None:
        return cached

    docs = fetch_all_pages(
        {"fq": f"codigo_ibge:{code}", "fl": "*", "sort": "id asc"}, label="field list"
    )
    if not docs:
        warnings.warn(f"The MI Social API has no document for municipality {code}.", stacklevel=2)
        return pd.DataFrame(
            {
                "field": pd.Series(dtype="object"),
                "unit": pd.Series(dtype="object"),
                "storage_type": pd.Series(dtype="object"),
                "in_dictionary": pd.Series(dtype="bool"),
                "first_period": pd.Series(dtype="object"),
                "last_period": pd.Series(dtype="object"),
            }
        )
    skip = {"id", "_version_", *ID_FIELDS}
    rows = [(f, d.get("anomes_s")) for d in docs for f in d if f not in skip]
    long = pd.DataFrame(rows, columns=["field", "period"])
    out = (
        long.groupby("field", as_index=False)
        .agg(first_period=("period", "min"), last_period=("period", "max"))
        .sort_values("field")
        .reset_index(drop=True)
    )
    out.insert(1, "unit", out["field"].map(unit_from_suffix))
    out.insert(2, "storage_type", out["field"].map(storage_from_suffix))
    out.insert(3, "in_dictionary", out["field"].isin(set(_dictionary()["field"])))
    return _cache.cache_set(key, out)
