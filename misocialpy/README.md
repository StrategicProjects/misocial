# misocialpy

<!-- badges: start -->
![License](https://img.shields.io/badge/license-MIT-darkviolet.svg)
![](https://img.shields.io/badge/devel%20version-0.4.0-blue.svg)
[![misocialpy](https://github.com/StrategicProjects/misocial/actions/workflows/misocialpy.yaml/badge.svg)](https://github.com/StrategicProjects/misocial/actions/workflows/misocialpy.yaml)
[![PyPI](https://img.shields.io/pypi/v/misocialpy.svg)](https://pypi.org/project/misocialpy/)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23504084.svg)](https://doi.org/10.5281/zenodo.23504084)
<!-- badges: end -->

Pandas-friendly Python interface to the **MI Social** API (Matriz de
Informação Social) of the Brazilian Ministry of Development and Social
Assistance (MDS/SAGI):
<https://aplicacoes.mds.gov.br/sagi/servicos/misocial>.

A port of the R package
[`misocialr`](https://github.com/StrategicProjects/misocial/tree/main/misocialr),
with the same
functions, name by name, as `ibgepy` does with `ibger`. Both versions read
the same field dictionary (`src/misocialpy/data/dictionary.csv`, a copy of
`misocialr/inst/extdata/`) and are tested against the same recorded
responses.

| Theme | Function | Content |
| --- | --- | --- |
| `cadunico` | `mds_cadunico()` | Cadastro Único: registered families and people, by income bracket |
| `bolsa_familia` | `mds_bolsa_familia()` | Bolsa Família programme: beneficiary families, benefits and transfers |
| `bpc_suas` | `mds_bpc_suas()` | BPC benefit and the social assistance network (CRAS, CREAS) |
| `suas_rede` | `mds_suas_rede()` | SUAS network (CadSUAS): CRAS, CREAS, Centro POP, day centres, shelters and staff per unit |
| `suas_financiamento` | `mds_suas_financiamento()` | FNAS transfers and balances of the municipal funds, and IGD-M |
| `pbf_condicionalidades` | `mds_pbf_condicionalidades()` | Education and health conditionality monitoring (SICON) and sanctions |
| `seguranca_alimentar` | `mds_seguranca_alimentar()` | PAA, Fomento Rural and cisterns |

Other functions: `mds_data()`, `mds_themes()`, `mds_fields()`,
`mds_api_fields()`, `mds_periods()`, `mds_localities()`,
`mds_drop_unpublished()`, `ibge_code7()`, `mds_clear_cache()`,
`set_verbose()`.

## Installation

```sh
pip install "git+https://github.com/StrategicProjects/misocial#subdirectory=misocialpy"

# or, from a local clone:
pip install ./misocialpy        # from the repository root
pip install .                   # from inside misocialpy/
```

Requires Python >= 3.9, pandas >= 1.3 and requests >= 2.25 (tested with
pandas 1.3.5 and requests 2.25.1 on Python 3.9, and with pandas 3.0.6 on
Python 3.14).

## Usage

```python
import misocialpy as m

m.mds_bolsa_familia(
    periods=[202508, 202509],
    localities=2611606,  # Recife (6 or 7 digits)
    fields=["qtd_familias_beneficiarias_bolsa_familia_i", "valor_repassado_bolsa_familia_f"],
)
#   ibge_code locality_name  period                                       field      unit       value
# 0   2611606        RECIFE  202508  qtd_familias_beneficiarias_bolsa_familia_i  Famílias    140350.0
# 1   2611606        RECIFE  202509  qtd_familias_beneficiarias_bolsa_familia_i  Famílias    139452.0
# 2   2611606        RECIFE  202508             valor_repassado_bolsa_familia_f        R$  92124240.0
# 3   2611606        RECIFE  202509             valor_repassado_bolsa_familia_f        R$  93354456.0
```

(Selected columns; output from 2026-10-19.)

- `periods`: `None` (last 12 months), `-n`, years (`2024`) and/or `YYYYMM`.
- `localities`: `"BR"`, states (`"PE"` or `26`), municipalities with 6 or 7
  digits.

The API answers **0** for months not yet published. `mds_periods()` shows
how many municipalities have a non-zero value in each month, and
`mds_drop_unpublished()` explicitly removes the trailing all-zero months;
`reference="brazil"` decides by the whole country and preserves legitimate
zeros of small selections.

Validation is the same as in the R package. Invalid input is a
`ValidationError`; an incomplete or malformed response (partial result,
missing facet, total that changes while paging, repeated document, no
municipality or several values) is a `ResponseError`; two values for the
same observation are a `DataConflictError`; a network or HTTP failure is an
`HttpError` (with `status`). All inherit from `MdsError`. None of this
enters the cache.

`mds_drop_unpublished()` never deletes a non-zero value; `action="flag"`
classifies the rows (`publication_status`, `publication_reason`,
`publication_reference`) without removing any.

- `misocialpy.set_timeout(300)`: maximum time per request (default 180 s);
  `misocialpy.set_verbose(False)` hides the messages.
- `df.attrs["retrieved_at"]`: date and time (UTC) of the query.
- `refresh=True` in `mds_periods()`, `mds_localities()` and
  `mds_api_fields()`; `mds_localities(period=)` picks the month of the
  list. Results are copies: editing them does not change the cache.
- `misocialpy.set_cache_ttl(3600)`: cache validity in seconds (default: the
  whole session).
- `mds_fields()` brings `nature` (`estoque`, `fluxo`, `fluxo anual`,
  `acumulado`, `taxa`, `média`, `índice`) and `nature_basis`; see the
  summing table in the R README.
- Paging by `cursorMark`.
- Queries by POST (avoids the HTTP 414 of long URLs); 3 attempts in total
  on 429/5xx and on connection failure, with `Retry-After` capped at 30 s.
- Accepts numpy scalars (`np.int64(202401)`) and integer-valued numbers
  (`26.0`), as in R. Years from 2000 to the year after the current one.

Development: `pip install -e ".[dev]"` (pytest, responses, ruff and build);
`pip install -e ".[test]"` for the tests only.

See the `misocialr` README for the notes on the fields.

## Tests

```sh
pytest            # offline, with recorded fixtures
pytest -m live    # against the real API
```
