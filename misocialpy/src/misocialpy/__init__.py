"""misocialpy — access the MDS MI Social API from Python.

A pandas-friendly port of the R package `misocialr`. Monthly municipal series
of the Cadastro Unico, the Bolsa Familia programme and its conditionalities,
the BPC, the social assistance network and its funding, and food security
programmes, from the Social Information Matrix of the
Brazilian Ministry of Development and Social Assistance (MDS/SAGI).

Quick start
-----------
>>> import misocialpy
>>> misocialpy.mds_bpc_suas(periods=2025, localities="PE")      # doctest: +SKIP
>>> misocialpy.mds_periods("bpc_ben_i", localities="PE")        # doctest: +SKIP
"""

from __future__ import annotations

from ._cache import clear_cache as mds_clear_cache
from ._cache import set_cache_ttl
from ._client import DataConflictError, HttpError, MdsError, ResponseError, set_timeout
from ._msg import set_verbose
from .data import (
    mds_bolsa_familia,
    mds_bpc_suas,
    mds_cadunico,
    mds_data,
    mds_pbf_condicionalidades,
    mds_seguranca_alimentar,
    mds_suas_financiamento,
    mds_suas_rede,
)
from .fields import mds_api_fields, mds_fields, mds_themes
from .localities import ibge_code7, mds_localities
from .periods import mds_periods
from .publication import mds_drop_unpublished
from .validation import ValidationError

__version__ = "0.4.0.post1"

__all__ = [
    "DataConflictError",
    "HttpError",
    "MdsError",
    "ResponseError",
    "ValidationError",
    "__version__",
    "ibge_code7",
    "mds_api_fields",
    "mds_bolsa_familia",
    "mds_bpc_suas",
    "mds_cadunico",
    "mds_clear_cache",
    "mds_data",
    "mds_drop_unpublished",
    "mds_fields",
    "mds_localities",
    "mds_pbf_condicionalidades",
    "mds_periods",
    "mds_seguranca_alimentar",
    "mds_suas_financiamento",
    "mds_suas_rede",
    "mds_themes",
    "set_cache_ttl",
    "set_timeout",
    "set_verbose",
]
