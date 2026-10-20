# SUAS funding: FNAS transfers, account balances and IGD-M

Shortcut for
[`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md)
with the curated funding fields (`mds_fields("suas_financiamento")`).

## Usage

``` r
mds_suas_financiamento(periods = NULL, localities = "BR", fields = NULL)
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

## Details

The transfer components add up to `suas_repasse_mun_vl_total_fundo_f`
(checked for Pernambuco in 06/2026 and 09/2026). The account balances do
**not** add up to the general total, so they should be read one by one.

## Examples

``` r
if (FALSE) { # interactive()
mds_suas_financiamento(periods = 2025, localities = 2611606)
}
```
