# Drop (or flag) months that were not published yet

The MI Social API answers `0`, not "missing", for months whose data has
not been published: the BPC series, for example, carries zeros for every
municipality up to December of the current year. Treating those zeros as
real would make the latest months look like a collapse of the programme.

## Usage

``` r
mds_drop_unpublished(
  data,
  today = Sys.Date(),
  reference = c("selection", "brazil"),
  action = c("drop", "flag")
)
```

## Arguments

- data:

  A tibble returned by
  [`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md)
  or a theme shortcut.

- today:

  Reference date for rule 1. Default
  [`Sys.Date()`](https://rdrr.io/r/base/Sys.time.html).

- reference:

  Where the last published month is read from: `"selection"` or
  `"brazil"`. See Details.

- action:

  `"drop"` (default) removes future and unpublished rows; `"flag"` keeps
  every row and adds the columns `publication_status` (`"published"`,
  `"future"`, `"unpublished"` or `"missing"`), `publication_reason` and
  `publication_reference`.

## Value

`data` without the dropped rows, or with the classification columns. A
message summarizes what was removed.

## Details

This helper applies an explicit rule, per field:

1.  months after the current month are **future**;

2.  months after the last month with a non-zero value are
    **unpublished**;

3.  a field with no non-zero value at all is unpublished entirely.

The "last month with a non-zero value" comes from `reference`:

- `"selection"` (default): the localities in `data`. Needs no request,
  but a small selection can legitimately end in zeros (a municipality
  without a CREAS unit, for example), and those zeros would be dropped.

- `"brazil"`: every municipality in the country, through
  [`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md)
  (two facet requests per field when not cached). A month is unpublished
  only when no municipality in Brazil has a non-zero value, which keeps
  legitimate zeros of small selections.

A non-zero value in `data` is never classified as unpublished. If the
national reference says a month with such a value is unpublished (a
cached reference older than the data, for instance), the reference is
requested again; if the contradiction remains, the month is kept and a
warning is raised.

This is an inference from the published values, not an official
publication date. A series can legitimately end in zeros, even
nationally; use `action = "flag"` to inspect the classification before
removing anything.

Rows with a missing `value` are never classified as zero: they are kept
and flagged as `"missing"`.

## Examples

``` r
x <- tibble::tibble(
  locality_id = "261160", period = c("202506", "202507", "202508"),
  field = "bpc_ben_i", value = c(98000, 98500, 0)
)
mds_drop_unpublished(x, today = as.Date("2025-12-01"))
#> Dropped 1 row of trailing all-zero months:
#> • bpc_ben_i: 202508
#> # A tibble: 2 × 4
#>   locality_id period field     value
#>   <chr>       <chr>  <chr>     <dbl>
#> 1 261160      202506 bpc_ben_i 98000
#> 2 261160      202507 bpc_ben_i 98500
mds_drop_unpublished(x, today = as.Date("2025-12-01"), action = "flag")
#> # A tibble: 3 × 7
#>   locality_id period field     value publication_status publication_reason      
#>   <chr>       <chr>  <chr>     <dbl> <chr>              <chr>                   
#> 1 261160      202506 bpc_ben_i 98000 published          NA                      
#> 2 261160      202507 bpc_ben_i 98500 published          NA                      
#> 3 261160      202508 bpc_ben_i     0 unpublished        after the last non-zero…
#> # ℹ 1 more variable: publication_reference <chr>
```
