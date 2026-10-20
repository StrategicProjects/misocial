# List municipalities available in the API

Returns the municipalities as identified by the MI Social API, with the
6-digit code the API uses and the official 7-digit IBGE code. The list
is read from one month (by default December of the last closed year),
paged and checked for completeness; it is cached for the session.

## Usage

``` r
mds_localities(state = NULL, period = NULL, refresh = FALSE)
```

## Arguments

- state:

  Optional state abbreviations (e.g. `"PE"`) or 2-digit IBGE state codes
  (e.g. `26`). `NULL` (default) returns all of Brazil.

- period:

  Month (`YYYYMM`) the list is read from. `NULL` (default) uses December
  of the last closed year. The territorial division of that month is
  what is returned.

- refresh:

  Logical. Ignore the cached list and ask the API again? Default
  `FALSE`.

## Value

A tibble with columns `locality_id` (6 digits, as in the API),
`ibge_code` (7 digits), `locality_name`, `state` and `region`. The month
and time of the request are kept in `attr(x, "period")` and
`attr(x, "retrieved_at")`.

## Examples

``` r
if (FALSE) { # interactive()
mds_localities("PE")
}
```
