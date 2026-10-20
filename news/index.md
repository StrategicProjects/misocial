# Changelog

## misocialr 0.4.0

- **Paging by `cursorMark`.** Pages are read by the sort key (`id`), not
  by position: documents added or removed while reading no longer shift
  the pages. Checked live: the same 185 documents for PE in 2024-01 as
  paging by `start`. The checks for a stable total, no repeated `id` and
  nothing missing remain.
- **Nature of each field in the dictionary** (`nature`, `nature_basis`
  in
  [`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md)):
  `estoque`, `fluxo`, `fluxo anual`, `acumulado`, `taxa`, `média` or
  `índice`, with the rule for summing across municipalities and months
  in the help page. 18 fields were measured on the monthly series (PE,
  2024-10 to 2025-12), 33 follow a measured field of the same group and
  81 come from the label and unit.
- Corrected label: the Fomento Rural field `..._ano_f` equals the
  monthly one in 14,755 of 14,755 municipality-month pairs (Brazil,
  2013–2026); it is the longest monthly series, not a yearly total.
- `options(misocialr.cache_ttl = seconds)`: optional cache validity (the
  default remains the session).
- DESCRIPTION: `cli (>= 3.6.1)` and `dplyr (>= 1.1.1)` — the declared
  minimum versions were not usable together today: `testthat` 3.2.1
  requires `cli >= 3.6.1`, and `dplyr` 1.1.0 calls the vctrs C routine
  `vec_is_vector`, removed in vctrs 0.7.0 (checked in the CI job that
  installs the minimum versions).

## misocialr 0.3.1

Fixes from the final report on 0.3.0 and the parallel verification.

- **Queries by POST.** With many months, fields and codes, the GET URL
  exceeded the server limit (HTTP 414, reproduced with 35 fields, 288
  months and 200 municipalities). The query now goes in the body; the
  same query returned 136,989 rows.
- `mds_drop_unpublished(action = "flag")` keeps the three classification
  columns also on an empty table (F2); a datetime `today` is read as a
  date; the period follows the same calendar rule as documents and
  facets.
- Non-finite values (`"NaN"`, `"Inf"`, `"1e999"`) are a response error;
  in deduplication, a missing value never replaces a known one, in any
  order (F4).
- Documents and facets with a month outside 01–12, facets with a
  repeated month, documents beyond `numFound` and incoherent facets
  (`n_nonzero` larger than `n_localities`, with a fresh read of the pair
  before the error) are errors and do not enter the cache (F5).
- A body that is not JSON is a `misocialr_error_response`, with the
  original error in `parent` (F6).
- `Retry-After` capped at 30 s per attempt and 120 s in total;
  `options(misocialr.retry_backoff = )`. Retries tested against a real
  local HTTP server (`webfakes`).
- `parse_periods()`: years from 2000 to the year after the current one.
- `parse_localities()`: `states` always character; round numeric codes
  without scientific notation in messages.
- Behaviour cases shared with the Python package
  (`tests/testthat/paridade/casos.json`).
- `LICENSE.md` with the full MIT text; `data-raw/record_fixtures.R`
  validates each recorded response and restores the previous fixtures if
  the replacement fails.
- Suggests: `jsonlite`, `webfakes`.

## misocialr 0.3.0

Fixes from the in-depth analysis of 0.2.1.

- Single response contract (`check_response()`): a partial result, a
  `responseHeader$status` other than 0, an invalid `numFound` and
  missing `docs` or `facet_counts` are errors, including in
  [`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md),
  [`mds_localities()`](https://strategicprojects.github.io/misocial/reference/mds_localities.md)
  and the field check. Only complete responses enter the cache (B1, B2,
  B8).
- [`mds_localities()`](https://strategicprojects.github.io/misocial/reference/mds_localities.md)
  pages, checks codes and repetitions and gains `period` and `refresh`
  (B2).
- [`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md)
  never removes a non-zero value: a contradictory national reference is
  queried again and, if still contradictory, the month is kept with a
  warning (B3). The period is normalised and checked as month 01 to 12,
  including factor and numeric (B6); `field`, `today` and infinite
  values are validated; a missing value is never treated as zero (B7).
  New `action = "flag"` (M2).
- A document without a valid `codigo_ibge` or `anomes_s` is an error
  (B4); a non-scalar value is an error, without flattening lists (B5);
  two different values for the same key are a conflict error (B4). A
  requested municipality inside a requested state is not queried twice.
- Paging: a `numFound` that changes between pages and a repeated `id`
  are errors (M5).
- [`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md)
  sums facets of disjoint blocks of up to 200 codes (M4) and gains
  `refresh`; canonical cache keys (M1).
- Classed errors (`misocialr_error_validation`, `_response`,
  `_conflict`, `_http`), with `status` and `parent` on the HTTP error;
  retry on connection failure; version in the user agent;
  `options(misocialr.quiet = TRUE)` (M8).
- `storage_type` in
  [`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md)
  and
  [`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md);
  unit `"unknown"` for `_s` and fields without suffix (M3).
- Local field validation even with `validate = FALSE` (M7); warning for
  a municipality without documents (M9);
  [`ibge_code7()`](https://strategicprojects.github.io/misocial/reference/ibge_code7.md)
  computes each code once (M6).
- DESCRIPTION: `httr2 (>= 1.0.4)`, `testthat (>= 3.2.1)` (B9).
- `data-raw/record_fixtures.R` records into a temporary folder and only
  replaces the fixtures after checking the result, keeping a copy in
  `api.bak/` (B10).
- CI workflows in `.github/workflows/` (M10).

## misocialr 0.2.1

Fixes from the external review of 0.2.0.

- An empty, `NA` or empty-string locality is an error; it used to become
  a query for the whole of Brazil.
- Every locality is validated, even next to `"BR"`.
- A 7-digit code with a wrong check digit is an error; the last digit
  used to be dropped (`2611600` queried Recife).
- An empty, `NA`, non-integer or negative period mixed with others is an
  error.
- A text field is an error (`regiao`); its values used to become `NA`
  and vanish. Identification fields (`municipio`, `anomes_s`…) cannot be
  requested as a measure.
- An empty page before `numFound`, a partial Solr result and a response
  without `response` are errors; reading used to finish with missing
  data.
- [`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md)
  pages through the whole history (previously up to 1,000 documents) and
  returns an empty table, with a warning, for a municipality without
  documents.
- [`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md)
  validates `period` and `value` and gains `reference = "brazil"`, which
  decides by the whole country.
- `options(misocialr.timeout = )` and `attr(x, "retrieved_at")`.
- Shortcuts with `fields = NULL`, as in Python;
  [`mds_themes()`](https://strategicprojects.github.io/misocial/reference/mds_themes.md)
  help page with the seven shortcuts.
- DESCRIPTION: `dplyr (>= 1.1.0)` and `purrr (>= 1.0.0)`.
- Errors from
  [`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md)
  reach the user without purrr’s “In index: 1” wrapper.

## misocialr 0.2.0

- Four new themes, with shortcuts:
  [`mds_suas_rede()`](https://strategicprojects.github.io/misocial/reference/mds_suas_rede.md),
  [`mds_suas_financiamento()`](https://strategicprojects.github.io/misocial/reference/mds_suas_financiamento.md),
  [`mds_pbf_condicionalidades()`](https://strategicprojects.github.io/misocial/reference/mds_pbf_condicionalidades.md)
  and
  [`mds_seguranca_alimentar()`](https://strategicprojects.github.io/misocial/reference/mds_seguranca_alimentar.md).
  The dictionary grows from 35 to 130 fields.
- The Bolsa Família quilombola and homeless fields leave the dictionary:
  the API returns the same value in both fields in every municipality
  and month.
- A field may belong to more than one theme (CRAS and CREAS).
- Fields with the `_l` suffix (long integer) now have unit `count`.

## misocialr 0.1.0

- First version:
  [`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md),
  shortcuts
  [`mds_cadunico()`](https://strategicprojects.github.io/misocial/reference/mds_cadunico.md),
  [`mds_bolsa_familia()`](https://strategicprojects.github.io/misocial/reference/mds_bolsa_familia.md)
  and
  [`mds_bpc_suas()`](https://strategicprojects.github.io/misocial/reference/mds_bpc_suas.md);
  discovery with
  [`mds_themes()`](https://strategicprojects.github.io/misocial/reference/mds_themes.md),
  [`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md),
  [`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md),
  [`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md)
  and
  [`mds_localities()`](https://strategicprojects.github.io/misocial/reference/mds_localities.md);
  [`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md),
  [`ibge_code7()`](https://strategicprojects.github.io/misocial/reference/ibge_code7.md)
  and
  [`mds_clear_cache()`](https://strategicprojects.github.io/misocial/reference/mds_clear_cache.md).
