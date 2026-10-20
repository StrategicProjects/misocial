# misocialr <img src="man/figures/logo.svg" align="right" height="139" />

<!-- badges: start -->
![License](https://img.shields.io/badge/license-MIT-darkviolet.svg)
![](https://img.shields.io/badge/devel%20version-0.4.0-blue.svg)
[![R-CMD-check](https://github.com/StrategicProjects/misocial/actions/workflows/misocialr.yaml/badge.svg)](https://github.com/StrategicProjects/misocial/actions/workflows/misocialr.yaml)
<!-- badges: end -->

Tidyverse-friendly R interface to the **MI Social** API (Matriz de
Informação Social) of the Brazilian Ministry of Development and Social
Assistance (MDS/SAGI):
<https://aplicacoes.mds.gov.br/sagi/servicos/misocial>.

The package follows the architecture of
[`ibger`](https://github.com/ropensci/ibger): a small English public API,
long-format tibble output, validation before any request, in-memory
per-session cache and offline tests with `httptest2` fixtures. The sibling
Python package,
[`misocialpy`](https://github.com/StrategicProjects/misocial/tree/main/misocialpy),
mirrors the same functions,
name by name.

## Themes

| Theme | Function | Content |
| --- | --- | --- |
| `cadunico` | `mds_cadunico()` | Cadastro Único: registered families and people, by income bracket |
| `bolsa_familia` | `mds_bolsa_familia()` | Bolsa Família programme: beneficiary families, benefits and transfers |
| `bpc_suas` | `mds_bpc_suas()` | BPC benefit and the social assistance network (CRAS, CREAS) |
| `suas_rede` | `mds_suas_rede()` | SUAS network (CadSUAS): CRAS, CREAS, Centro POP, day centres, shelters and staff per unit |
| `suas_financiamento` | `mds_suas_financiamento()` | FNAS transfers and balances of the municipal funds, and IGD-M |
| `pbf_condicionalidades` | `mds_pbf_condicionalidades()` | Education and health conditionality monitoring (SICON) and sanctions |
| `seguranca_alimentar` | `mds_seguranca_alimentar()` | PAA, Fomento Rural and cisterns |

The fields of each theme are in `mds_fields()`. Any other field of the API
(`mds_api_fields()`) can be requested by name in `mds_data()`.

## Installation

```r
# install.packages("remotes")
remotes::install_github("StrategicProjects/misocial", subdir = "misocialr")
```

Requires R >= 4.1, httr2 >= 1.0.4, cli >= 3.6.1, dplyr >= 1.1.1 and
purrr >= 1.0.0 (tests: testthat >= 3.2.1).

## Usage

```r
library(misocialr)

mds_bolsa_familia(
  periods = c(202508, 202509),
  localities = 2611606,            # Recife (6 or 7 digits)
  fields = c("qtd_familias_beneficiarias_bolsa_familia_i",
             "valor_repassado_bolsa_familia_f")
)
#> # A tibble: 4 × 9  (selected columns)
#>   ibge_code locality_name period field                                      unit        value
#> 1 2611606   RECIFE        202508 qtd_familias_beneficiarias_bolsa_familia_i Famílias   140350
#> 2 2611606   RECIFE        202509 qtd_familias_beneficiarias_bolsa_familia_i Famílias   139452
#> 3 2611606   RECIFE        202508 valor_repassado_bolsa_familia_f            R$       92124240
#> 4 2611606   RECIFE        202509 valor_repassado_bolsa_familia_f            R$       93354456
```

Accepted formats:

- `periods`: `NULL` (last 12 months), `-n` (last *n* months), years
  (`2024`) and/or `YYYYMM` months (`202401`).
- `localities`: `"BR"`, states (`"PE"` or `26`), municipalities with 6 or 7
  digits, combined freely.

Output columns: `locality_id` (6 digits, as in the API), `ibge_code`
(7 digits), `locality_name`, `state`, `period`, `field`, `label`, `unit`,
`value`.

## Months not yet published

The API answers **0**, not "missing", for months that were not published
yet. `mds_periods()` shows this: `n_nonzero` counts only the municipalities
with a non-zero value.

```r
mds_periods("bpc_ben_i", localities = "PE") |> tail(5)
#>   period n_localities n_nonzero
#> 1 202608          185       185
#> 2 202609          185         0
#> 3 202610          185         0
#> 4 202611          185         0
#> 5 202612          185         0
```

`mds_drop_unpublished()` removes those zeros explicitly: future months and
months after the last month with a non-zero value. A zero in the middle of
the series, followed by a month with a value, is kept. The outputs above
come from queries made on 2026-10-19.

The "last month with a value" can come from two places:

- `reference = "selection"` (default): the localities of the query itself.
  No extra request, but in a small selection a legitimate trailing zero (a
  municipality without a CREAS, say) is removed as well.
- `reference = "brazil"`: the whole country, via `mds_periods()`. A month is
  only removed when no municipality in Brazil has a value; legitimate zeros
  of small selections are preserved.

## Validation and errors

The query is checked before any data request, and the cases below are
errors with a message, instead of an empty or silently different result:

- empty locality (`character(0)`), `NA` or empty string, which used to turn
  into a query for the whole of Brazil;
- an invalid locality even next to `"BR"` (`c("BR", "Recifex")`);
- a 7-digit code with a wrong check digit (`2611600` instead of `2611606`,
  which used to query Recife);
- an empty, `NA`, non-integer (`-1.9`) period, or a negative period mixed
  with others;
- a text field (`regiao`) or an identification field (`municipio`): the
  package only returns numeric values;
- an incomplete or malformed API response: an empty page before `numFound`,
  a partial Solr result, a negative or non-integer `numFound`, missing
  `docs` or `facet_counts`, a total that changes while paging, a document
  read twice, a document without municipality or month, a field with more
  than one value in the same document;
- two different values for the same municipality, month and field.

Every response is checked **before** it is used or cached: a failure of the
source does not become "no data" for the rest of the session.

Errors are classed, for programmatic handling: `misocialr_error_validation`
(input), `misocialr_error_response` (incomplete response),
`misocialr_error_conflict` (the source contradicts itself) and
`misocialr_error_http` (network, with `status` and the original error in
`parent`); all inherit from `misocialr_error`. A requested municipality
with no document raises the warning `misocialr_warning_missing`.

## Unpublished months: remove or flag

`mds_drop_unpublished()` never deletes a non-zero value. With
`reference = "brazil"`, if the national reference says that a month with a
value was not published, it is queried again; if the contradiction remains,
the month is kept with a warning. To inspect before removing:

```r
mds_drop_unpublished(x, action = "flag")
# adds publication_status ("published", "future", "unpublished",
# "missing"), publication_reason and publication_reference
```

This is an inference from the published values, not an official publication
date.

## Options

- `options(misocialr.timeout = 300)`: maximum time per request, in seconds
  (default 180).
- `options(misocialr.quiet = TRUE)`: hides the progress messages.
- `attr(x, "retrieved_at")`: date and time of the query that produced `x`
  (also in `mds_periods()` and `mds_localities()`).
- `options(misocialr.cache_ttl = 3600)`: cache validity, in seconds (the
  default is the whole session).
- Cache: `refresh = TRUE` in `mds_periods()`, `mds_localities()` and
  `mds_api_fields()` queries a result again; `mds_clear_cache()` clears
  everything. Equivalent selections (`c("PE", "PB")` and `c("PB", "PE")`)
  share the result.
- `mds_localities(period = )` picks the month of the municipality list.
- Retries: up to 3 attempts in total on 429/5xx and on connection failure,
  with `Retry-After` capped at 30 s per attempt and 120 s in total;
  `options(misocialr.retry_backoff = 2)` sets the wait between them.
- Queries go by **POST**: with many months, fields and municipalities, the
  URL of a GET would exceed the server limit (HTTP 414).
- `periods` accepts years from 2000 to the year after the current one (the
  API starts in 2003-01).

## Summing safely

`mds_fields()` tells the nature of each field (`nature`) and where that
classification comes from (`nature_basis`):

| `nature` | Sum across municipalities | Sum across months |
|---|---|---|
| `estoque` (count in the month) | yes | no |
| `fluxo` (value of the month) | yes | yes |
| `fluxo anual` (one value per year, in December) | yes | one value per year |
| `acumulado` (running total) | yes | no |
| `taxa`, `média`, `índice` | no | no |

`nature_basis = "medido"` means the monthly series was inspected (a running
total only grows; a monthly value oscillates and restarts); the others are
inferences from the group or from the label and unit.

## Known limits

- Paging uses `cursorMark`, which walks by key rather than by position; the
  package still flags a changing total and a repeated document. A long
  query sees the source as it was at each page, not as a single snapshot.
- The classification of unpublished months is an inference from the values,
  not an official publication date.
- R and Python follow the same behaviour cases
  (`tests/testthat/paridade/casos.json`), but parity is only guaranteed for
  what those cases cover.

## Notes on the fields

- `storage_type` says how the value is stored in the API (suffix `_i`,
  `_l`, `_f`, `_d`, `_s`), not what it measures.
- The API publishes no data dictionary. The labels in `mds_fields()` are a
  reading of the technical names; all 130 fields were checked against the
  API (`data-raw/check_dictionary.R`). CRAS and CREAS appear in two themes
  (`bpc_suas` and `suas_rede`).
- The Cadastro Único income brackets are disjoint and sum: in Brazil,
  2025-08, poverty (19,452,231) + low income (7,828,004) = up to ½ minimum
  wage (27,280,235). "Low income" is the bracket **between** the poverty
  line and ½ minimum wage.
- FNAS transfers: the components sum to the total (PE, 2026-06: 7,625,605,
  including the "fundo a fundo" line; 2026-09: 11,684,831). The **account
  balances do not sum** to the overall total; read them one by one.
  Components that stopped being published were left out (SUAS management
  since 2022, PSE média/alta since 2011, PAB since 2023).
- IGD-M: value without incentives + incentives = value with incentives (PE,
  2026-08). `igdm_f` is an index: do not sum across municipalities.
- Conditionalities (SICON, since 2023): in education, monitored + no
  information = target group (Recife, 2026-07: 110,464 + 16,896 = 127,360);
  in health, children + women = people. Warning + blocking + suspension +
  cancellation = sanctions, for BF (family benefit) and BVA (benefit of
  16–17-year-olds), as in MDS Informe Bolsa Família no. 44. External check:
  Brazil, 2024-03, equal to Informe no. 37 in all six numbers (BF 201,726
  warnings, 80,543 blockings, 64,915 suspensions; BVA 74,853, 40,474 and
  50,015); 2024-05 equal to the state table of Informe no. 44 (BF 230,466,
  44,247 and 36,851).
- Cisterns are **cumulative** counts: do not sum months.
- `pbf_qtd_familias_quilombolas_benef_i` and
  `pbf_qtd_familias_sit_rua_benef_i` have the **same value** in every
  municipality and month (PE 2020–2026: 14,615 of 14,615 pairs; Brazil
  2025-09: 5,570 of 5,570, summing 283,923), and Recife shows 1 homeless
  family. They were left out of the dictionary until the source fixes them.
- The Cadastro Único has no month **2025-04** in the API itself
  (`mds_periods("cadun_qtd_familias_cadastradas_i")` jumps from 202503 to
  202505).
- `pbf_qtd_familias_benef_i` is **not** the total of Bolsa Família families
  (Recife, 2024-02: 9,847, against 146,737 in
  `qtd_familias_beneficiarias_bolsa_familia_i`). It is out of the
  dictionary.

## Development

```sh
Rscript -e 'testthat::test_local(".")'   # tests, offline
Rscript data-raw/record_fixtures.R        # re-records fixtures (network)
Rscript data-raw/check_dictionary.R       # checks the dictionary against the API (network)
```
