# Convert 6-digit MDS municipality codes to 7-digit IBGE codes

The MI Social API identifies municipalities by the first six digits of
the IBGE code (without the check digit). This helper restores the
official 7-digit code, using the IBGE check-digit rule plus the table of
municipalities that are exceptions to it.

## Usage

``` r
ibge_code7(x)
```

## Arguments

- x:

  Character or numeric vector of 6-digit codes.

## Value

A character vector of 7-digit IBGE codes (`NA` for inputs that are not 6
digits).

## Examples

``` r
ibge_code7(c(261160, "260790"))
#> [1] "2611606" "2607901"
```
