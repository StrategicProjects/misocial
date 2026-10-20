# Fetch MI Social data

Main retrieval function. Returns monthly municipal values of the
requested fields as a tidy long tibble: one row per field x municipality
x month in which the API has a value.

## Usage

``` r
mds_data(fields, periods = NULL, localities = "BR", validate = TRUE)
```

## Arguments

- fields:

  Character vector of field names. See
  [`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md)
  for the curated list and
  [`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md)
  for everything the API has.

- periods:

  Periods to fetch:

  - `NULL` (default): the last 12 months up to the current month;

  - a negative number `-n`: the last `n` months up to the current month;

  - years (`2024`) and/or months as `YYYYMM` (`202401`, `"202401"`).

- localities:

  `"BR"` (all of Brazil), state abbreviations (`"PE"`) or 2-digit state
  codes (`26`), and/or 6- or 7-digit IBGE municipality codes
  (`2611606`), in any combination. Default `"BR"`.

- validate:

  Logical. Check that fields not in the dictionary exist in the API
  before requesting data? Default `TRUE`. Local checks (names, periods,
  localities) always run.

## Value

A tibble with columns `locality_id` (6-digit code used by the API),
`ibge_code` (7-digit IBGE code), `locality_name`, `state`, `period`
(`"YYYYMM"`), `field`, `label`, `unit` and `value` (double). The time of
the request is kept in `attr(x, "retrieved_at")`.

## Details

The query is validated before any data request (field names, period
format, locality codes), then paged through Solr and, when many
municipality codes are given, split into several requests whose results
are bound together.

Values are returned as published. Note that the API answers `0` for
months that were not published yet; use
[`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md)
to remove those trailing zeros explicitly.

Only numeric fields are supported: a field whose values are text (such
as `regiao`) is an error rather than an empty result.

Every response is checked before it is used: a partial or malformed
answer, a total that changes while paging, a document read twice, a
document without municipality or month, a field with several values in
one document, or two different values for the same municipality, month
and field are errors (classes `misocialr_error_response` and
`misocialr_error_conflict`). A requested municipality that returns no
document raises a warning.

Options: `misocialr.timeout` (seconds per request, default 180) and
`misocialr.quiet` (`TRUE` hides the progress messages).

## Examples

``` r
if (FALSE) { # interactive()
mds_data(
  c("bpc_ben_i", "cadsuas_qtd_cras_i"),
  periods = 2025,
  localities = c(2611606, 2607901)
)
}
```
