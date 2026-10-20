# Bolsa Familia conditionalities: education and health follow-up

Shortcut for
[`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md)
with the curated conditionality fields
(`mds_fields("pbf_condicionalidades")`): the SICON series from 2023 on
(education, health, warnings, blocks, suspensions and cancellations) and
the IGD-M follow-up rates, available since 2015.

## Usage

``` r
mds_pbf_condicionalidades(periods = NULL, localities = "BR", fields = NULL)
```

## Arguments

- periods:

  Periods to fetch:

  - `NULL` (default): the last 12 months up to the current month;

  - a negative number `-n`: the last `n` months up to the current month;

  - years (`2024`) and/or months as `YYYYMM` (`202401`, `"202401"`).

- localities:

  `"BR"` (all of Brazil), state abbreviations (`"PE"`) or 2-digit state
  codes (`26`), and/or 6- or 7-digit IBGE municipality codes
  (`2611606`), in any combination. Default `"BR"`.

- fields:

  Fields to fetch. `NULL` (default) fetches every curated field of the
  theme.

## Value

A tibble in the format of
[`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md).

## Examples

``` r
if (FALSE) { # interactive()
mds_pbf_condicionalidades(periods = 2026, localities = "PE")
}
```
