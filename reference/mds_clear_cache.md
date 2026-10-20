# Clear the session cache

Removes all cached localities, field lists, periods and field checks,
forcing fresh API calls on subsequent requests. To refresh a single
result, use the `refresh` argument of
[`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md),
[`mds_localities()`](https://strategicprojects.github.io/misocial/reference/mds_localities.md)
or
[`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md).

## Usage

``` r
mds_clear_cache()
```

## Value

No return value, called for side effects.

## Examples

``` r
mds_clear_cache()
#> ✔ MI Social cache cleared.
```
