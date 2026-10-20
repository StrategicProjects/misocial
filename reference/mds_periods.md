# List the periods available for a field

Uses Solr facets to count, for each month, how many municipalities have
a value for the field and how many of those values are non-zero.

## Usage

``` r
mds_periods(field, localities = "BR", refresh = FALSE)
```

## Arguments

- field:

  A single field name (see
  [`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md)).

- localities:

  Localities to restrict the count to; same forms as in
  [`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md).
  Default `"BR"`.

- refresh:

  Logical. Ignore the cached result and ask the API again? Default
  `FALSE`.

## Value

A tibble with columns `period` (`"YYYYMM"`), `n_localities` and
`n_nonzero`, ordered by period. The time of the request is kept in
`attr(x, "retrieved_at")`.

## Details

The second count matters: the API returns `0` for months that have not
been published yet (for instance, the BPC series carries zeros for every
municipality up to the end of the current year). A month where
`n_nonzero` is 0 for the whole selection is almost always unpublished,
not a true zero. See
[`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md).

Results are cached for the session. Large selections are counted in
blocks of at most 200 municipality codes (the same split as
[`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md));
the blocks do not overlap, so their counts are summed.

## Examples

``` r
if (FALSE) { # interactive()
mds_periods("bpc_ben_i", localities = "PE")
}
```
