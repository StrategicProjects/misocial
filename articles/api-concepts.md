# Understanding the MI Social API

## Introduction

The [MI Social
API](https://aplicacoes.mds.gov.br/sagi/servicos/misocial) (Matriz de
Informação Social) is the service behind the public panels of SAGI, the
information office of the Brazilian Ministry of Development and Social
Assistance (MDS). It is a thin HTTP layer over an Apache **Solr** index,
and understanding that shapes everything the package does: what a
document is, why unpublished months come back as zero, and why every
response is checked before it is used.

``` r

library(misocialr)
```

## Documents: one municipality, one month

Each Solr document holds every published value for one municipality in
one month. A document carries identification fields (`codigo_ibge`,
`municipio`, `anomes_s`, `regiao`…) and one field per published measure.
The API has no data dictionary of its own;
[`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md)
lists, month by month, which fields exist in the documents of one
municipality:

``` r

fields_recife <- mds_api_fields(2611606)
fields_recife
#> # A tibble: 1,230 × 6
#>    field               unit  storage_type in_dictionary first_period last_period
#>    <chr>               <chr> <chr>        <lgl>         <chr>        <chr>      
#>  1 acessuas_qtd_grupo… count integer      FALSE         202208       202208     
#>  2 acessuas_qtd_ofici… count integer      FALSE         202208       202208     
#>  3 acessuas_qtd_parti… count integer      FALSE         202208       202208     
#>  4 acessuas_qtd_parti… count integer      FALSE         202208       202208     
#>  5 acessuas_qtd_parti… count integer      FALSE         202208       202208     
#>  6 acessuas_qtd_vagas… count integer      FALSE         202208       202208     
#>  7 agricultores_forne… count integer      TRUE          201112       202607     
#>  8 alimentabr_qtde_ag… count integer      FALSE         201112       202607     
#>  9 anomes              unkn… untyped      FALSE         200301       202612     
#> 10 aux_emerg_21_cadun… count integer      FALSE         202104       202104     
#> # ℹ 1,220 more rows
```

Fields appear and disappear over time (programmes start, are renamed or
stop being published), which is why the result has one row per field x
month.

## Field names and storage suffixes

The last token of a field name says how the value is stored in Solr, and
nothing more:

| Suffix | Storage                  |
|--------|--------------------------|
| `_i`   | integer                  |
| `_l`   | long integer             |
| `_f`   | float                    |
| `_d`   | double                   |
| `_s`   | string (never a measure) |

[`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md)
and
[`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md)
expose it as `storage_type`. The suffix does not say what the value
*measures*: that is the role of the dictionary.

## The curated dictionary

The package ships a dictionary of 130 fields, grouped in seven themes,
each with a shortcut function:

``` r

mds_themes()
#> # A tibble: 7 × 4
#>   theme                 name                               description  n_fields
#>   <chr>                 <chr>                              <chr>           <int>
#> 1 cadunico              Cadastro Único                     Famílias e …       12
#> 2 bolsa_familia         Programa Bolsa Família             Famílias be…       11
#> 3 bpc_suas              BPC e rede socioassistencial       Benefício d…       10
#> 4 suas_rede             Rede socioassistencial (CadSUAS)   Unidades CR…       19
#> 5 suas_financiamento    Financiamento do SUAS              Repasses e …       22
#> 6 pbf_condicionalidades Condicionalidades do Bolsa Família Acompanhame…       35
#> 7 seguranca_alimentar   Segurança alimentar e nutricional  PAA, Foment…       23
```

Every entry was checked against the published values. Besides a label
and a unit, the dictionary says the **nature** of each field, which
decides what can be summed:

``` r

subset(mds_fields("bolsa_familia"),
       select = c(field, nature, nature_basis))
#> # A tibble: 11 × 3
#>    field                                      nature  nature_basis    
#>    <chr>                                      <chr>   <chr>           
#>  1 qtd_familias_beneficiarias_bolsa_familia_i estoque rótulo e unidade
#>  2 qtd_pessoas_beneficiarias_bolsa_familia_i  estoque rótulo e unidade
#>  3 valor_repassado_bolsa_familia_f            fluxo   rótulo e unidade
#>  4 pbf_vlr_medio_benef_f                      média   rótulo e unidade
#>  5 familias_pbf_pobreza_i                     estoque rótulo e unidade
#>  6 familias_pbf_extrema_pobreza_i             estoque rótulo e unidade
#>  7 pbf_qtd_familias_indigenas_benef_i         estoque rótulo e unidade
#>  8 pbf_qtd_benef_primeira_infancia_bpi_i      estoque rótulo e unidade
#>  9 pbf_qtd_benef_gestantes_i                  estoque rótulo e unidade
#> 10 pbf_qtd_benef_7_a_17_anos_i                estoque rótulo e unidade
#> 11 pbf_perc_familias_benef_rf_mulher_d        taxa    rótulo e unidade
```

| `nature` | Sum across municipalities | Sum across months |
|----|----|----|
| `estoque` (count in the month) | yes | no |
| `fluxo` (value of the month) | yes | yes |
| `fluxo anual` (one value per year) | yes | one value per year |
| `acumulado` (running total) | yes | no |
| `taxa`, `média`, `índice` | no | no |

`nature_basis` says where the classification comes from: `"medido"`
means the monthly series itself was inspected (a running total only
grows; a monthly value oscillates and restarts); the other values are
inferences from a measured field of the same group or from the label and
unit.

## Zero is not “missing”

Solr has no notion of “not published yet”: a month that was not
published comes back as **0**, indistinguishable at the document level
from a real zero. The package exposes the distinction through facets —
counts of municipalities with a non-zero value per month:

``` r

periods_pe <- mds_periods("bpc_ben_i", localities = "PE")
tail(periods_pe, 5)
#> # A tibble: 5 × 3
#>   period n_localities n_nonzero
#>   <chr>         <int>     <int>
#> 1 202608          185       185
#> 2 202609          185         0
#> 3 202610          185         0
#> 4 202611          185         0
#> 5 202612          185         0
```

A trailing run of months where `n_nonzero` is 0 is the unpublished tail.
[`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md)
removes it explicitly — and never removes a non-zero value:

- `reference = "selection"` (default) decides from the localities of the
  query itself, with no extra request;
- `reference = "brazil"` decides from the whole country, which preserves
  legitimate zeros of small selections (a municipality without a CREAS,
  say);
- `action = "flag"` classifies the rows (`publication_status`,
  `publication_reason`, `publication_reference`) instead of removing
  them.

This is an inference from the published values, not an official
publication date.

## How misocialr talks to the API

Every query goes through the same pipeline:

1.  **Validation before any request.** Locality codes (including the
    IBGE check digit), periods and field names are checked locally; a
    text field requested as a measure is an error, not an empty result.

``` r

mds_data("bpc_ben_i", periods = 2025, localities = 2611600)
#> Error:
#> ! Wrong check digit in municipality code(s): "2611600".
#> ℹ Did you mean "2611606"?
```

2.  **Queries by POST.** With many months, fields and municipality
    codes, the URL of a GET would exceed the server limit (HTTP 414), so
    the query goes in the request body.

3.  **Paging by `cursorMark`.** Pages are read by the sort key rather
    than by position, so documents added or removed while reading do not
    shift the pages. The package still verifies that the total does not
    change and that no document is read twice.

4.  **A response contract.** A partial Solr result, a missing `docs` or
    `facet_counts`, a document without municipality or month, a
    non-scalar or non-finite value, and two different values for the
    same municipality, month and field are all errors with a class
    (`misocialr_error_response`, `misocialr_error_conflict`,
    `misocialr_error_http`, all inheriting from `misocialr_error`) —
    never silently incomplete data.

5.  **A per-session cache.** Only responses that pass the contract are
    cached. `refresh = TRUE` re-queries a result,
    `options(misocialr.cache_ttl = )` gives the cache a validity in
    seconds, and
    [`mds_clear_cache()`](https://strategicprojects.github.io/misocial/reference/mds_clear_cache.md)
    clears everything.

## How the functions map to the API

| Function | API mechanism |
|----|----|
| [`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md), theme shortcuts | documents, paged by `cursorMark` |
| [`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md) | documents of one municipality, field inventory |
| [`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md) | facets: non-zero counts per month |
| [`mds_localities()`](https://strategicprojects.github.io/misocial/reference/mds_localities.md) | documents of one month, one per municipality |
| [`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md) | facets (with `reference = "brazil"`) |
| [`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md), [`mds_themes()`](https://strategicprojects.github.io/misocial/reference/mds_themes.md) | local dictionary, no request |

## Further reading

- [`vignette("getting-started")`](https://strategicprojects.github.io/misocial/articles/getting-started.md)
  for the basic workflow.
- [`vignette("bolsa-familia")`](https://strategicprojects.github.io/misocial/articles/bolsa-familia.md)
  for a worked analysis with plots.
- The
  [README](https://github.com/StrategicProjects/misocial/tree/main/misocialr)
  collects the field-by-field notes (income brackets that sum, FNAS
  components, conditionality identities, known gaps in the source).
