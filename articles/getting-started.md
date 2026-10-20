# Getting started with misocialr

## Overview

**misocialr** reads the [MI Social
API](https://aplicacoes.mds.gov.br/sagi/servicos/misocial) of the
Brazilian Ministry of Development and Social Assistance (MDS/SAGI):
monthly values for every municipality, from the Cadastro Unico, the
Bolsa Familia programme, the BPC benefit, the social assistance network
and its funding, Bolsa Familia conditionalities and food security
programmes.

Every retrieval function returns a long tibble with one row per field x
municipality x month in which the API has a value.

``` r

library(misocialr)
```

## Themes and fields

The package ships a curated dictionary. Each theme has a shortcut
function.

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

The API has no data dictionary of its own: labels are a reading of the
technical names, checked against the published values. Any other field
can be requested by name in
[`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md);
[`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md)
lists what the API publishes for one municipality.

## Retrieving data

Periods are months (`YYYYMM`), years, or `-n` for the last *n* months.
Localities are `"BR"`, states (`"PE"` or `26`) or IBGE municipality
codes with 6 or 7 digits, in any combination.

``` r

recife <- mds_bolsa_familia(
  periods = c(202508, 202509),
  localities = 2611606,
  fields = c("qtd_familias_beneficiarias_bolsa_familia_i",
             "valor_repassado_bolsa_familia_f")
)
recife[, c("ibge_code", "period", "field", "value")]
#> # A tibble: 4 × 4
#>   ibge_code period field                                         value
#>   <chr>     <chr>  <chr>                                         <dbl>
#> 1 2611606   202508 qtd_familias_beneficiarias_bolsa_familia_i   140350
#> 2 2611606   202509 qtd_familias_beneficiarias_bolsa_familia_i   139452
#> 3 2611606   202508 valor_repassado_bolsa_familia_f            92124240
#> 4 2611606   202509 valor_repassado_bolsa_familia_f            93354456
```

The API identifies municipalities by the first six digits of the IBGE
code;
[`ibge_code7()`](https://strategicprojects.github.io/misocial/reference/ibge_code7.md)
restores the official code, including the nine municipalities whose code
does not follow the check-digit rule.

``` r

ibge_code7(c("261160", "261153"))
#> [1] "2611606" "2611533"
```

## Months not published yet

The API answers `0`, not “missing”, for months that were not published.
[`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md)
counts, per month, the municipalities with a value and those with a
non-zero value:

``` r

tail(mds_periods("bpc_ben_i", localities = "PE"), 5)
#> # A tibble: 5 × 3
#>   period n_localities n_nonzero
#>   <chr>         <int>     <int>
#> 1 202608          185       185
#> 2 202609          185         0
#> 3 202610          185         0
#> 4 202611          185         0
#> 5 202612          185         0
```

[`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md)
returns the values as published.
[`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md)
removes future months and trailing months in which every returned
locality is zero, and says what it removed:

``` r

bpc <- mds_bpc_suas(periods = 2026, localities = "PE", fields = "bpc_ben_i")
range(bpc$period)
#> [1] "202601" "202612"
```

``` r

bpc <- mds_drop_unpublished(bpc)
#> Dropped 370 rows of future months.
#> Dropped 370 rows of trailing all-zero months:
#> • bpc_ben_i: 202609, 202610
range(bpc$period)
#> [1] "202601" "202608"
```

## Checks behind the labels

Where fields are parts of a total, the parts were summed against the
total before labelling. For example, the Cadastro Unico income brackets
are disjoint:

``` r

cad <- mds_cadunico(
  periods = 202508, localities = "BR",
  fields = c("cadun_qtd_familias_cadastradas_pobreza_pbf_i",
             "cadun_qtd_familias_cadastradas_baixa_renda_i",
             "cadun_qtd_familias_cadastradas_rfpc_ate_meio_sm_i")
)
totals <- tapply(cad$value, cad$field, sum)
totals
#>      cadun_qtd_familias_cadastradas_baixa_renda_i 
#>                                           7828004 
#>      cadun_qtd_familias_cadastradas_pobreza_pbf_i 
#>                                          19452231 
#> cadun_qtd_familias_cadastradas_rfpc_ate_meio_sm_i 
#>                                          27280235
totals[["cadun_qtd_familias_cadastradas_pobreza_pbf_i"]] +
  totals[["cadun_qtd_familias_cadastradas_baixa_renda_i"]] ==
  totals[["cadun_qtd_familias_cadastradas_rfpc_ate_meio_sm_i"]]
#> [1] TRUE
```

so “baixa renda” is the bracket between the poverty line and half a
minimum wage. The other checks are listed in the package README.

    #> Built on 2026-10-20 against the live API.
