# List the fields published for one municipality

Fetches the full documents of one municipality over all months (paging
through the whole history) and returns the union of the field names
found, with the first and last period in which each field appears. MI
Social documents are sparse (a field only exists in the months it was
published), which is why the whole history is scanned rather than a
single document.

## Usage

``` r
mds_api_fields(locality = 261160, refresh = FALSE)
```

## Arguments

- locality:

  6- or 7-digit IBGE code of the municipality whose history is scanned.
  Defaults to Recife (`261160`).

- refresh:

  Logical. Ignore the cached result and ask the API again? Default
  `FALSE`.

## Value

A tibble with columns `field`, `unit` (inferred from the suffix;
`"unknown"` when the suffix does not say), `storage_type`,
`in_dictionary`, `first_period` and `last_period`. Empty, with a
warning, when the API has no document for the municipality.

## Details

This is the catalogue of **one** municipality, not of the whole API:
fields that exist only elsewhere (a regional CREAS, for instance) do not
appear. Scan other municipalities to widen the search.

Results are cached for the session.

## Examples

``` r
if (FALSE) { # interactive()
mds_api_fields()
}
```
