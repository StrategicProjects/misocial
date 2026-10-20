# List curated fields

Returns the curated dictionary of MI Social fields: the technical field
name used by the API, a readable Portuguese label, the unit and how the
value is stored in the API.

## Usage

``` r
mds_fields(theme = NULL)
```

## Arguments

- theme:

  Optional theme id (see
  [`mds_themes()`](https://strategicprojects.github.io/misocial/reference/mds_themes.md)).
  `NULL` (default) returns all themes.

## Value

A tibble with columns `theme`, `field`, `label`, `unit`, `nature`,
`nature_basis` and `storage_type`.

## Details

The API itself has no data dictionary. Labels are a reading of the
technical names, checked against the published values; units are what is
counted (`Famílias`, `Pessoas`, `R$`, `%`...). `storage_type` is the
Solr type given by the suffix (`_i` integer, `_l` long, `_f` float, `_d`
double, `_s` string) and says nothing about the unit. Any other field
published by the API (see
[`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md))
can still be requested by name in
[`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md).

`nature` says how a field may be aggregated:

|  |  |  |
|----|----|----|
| `nature` | Across municipalities | Across months |
| `estoque` (count at the month) | sum | do not sum |
| `fluxo` (amount in the month) | sum | sum |
| `fluxo anual` (one value a year, in December) | sum | one value a year |
| `acumulado` (running total) | sum | do not sum |
| `taxa`, `média`, `índice` | do not sum | do not sum |

`nature_basis` says where the classification comes from: `medido` (the
monthly series was inspected: a running total only grows, an amount of
the month varies and restarts), `mesmo grupo de um campo medido`, or
`rótulo e unidade` (inferred from the label and unit, not inspected).

## Examples

``` r
mds_fields("bpc_suas")
#> # A tibble: 10 × 7
#>    theme    field                 label   unit  nature nature_basis storage_type
#>    <chr>    <chr>                 <chr>   <chr> <chr>  <chr>        <chr>       
#>  1 bpc_suas bpc_ben_i             Benefi… Pess… estoq… rótulo e un… integer     
#>  2 bpc_suas bpc_idoso_ben_i       Benefi… Pess… estoq… rótulo e un… integer     
#>  3 bpc_suas bpc_pcd_ben_i         Benefi… Pess… estoq… rótulo e un… integer     
#>  4 bpc_suas bpc_val_f             Valor … R$    fluxo  medido       float       
#>  5 bpc_suas bpc_idoso_val_f       Valor … R$    fluxo  rótulo e un… float       
#>  6 bpc_suas bpc_pcd_val_f         Valor … R$    fluxo  rótulo e un… float       
#>  7 bpc_suas bpc_idoso_val_medio_f Valor … R$    média  rótulo e un… float       
#>  8 bpc_suas bpc_pcd_val_medio_f   Valor … R$    média  rótulo e un… float       
#>  9 bpc_suas cadsuas_qtd_cras_i    Unidad… Unid… estoq… rótulo e un… integer     
#> 10 bpc_suas cadsuas_qtd_creas_i   Unidad… Unid… estoq… rótulo e un… integer     
```
