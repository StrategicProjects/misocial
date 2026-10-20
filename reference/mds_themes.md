# List the themes covered by the package

Each theme groups a curated set of MI Social fields (see
[`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md))
and has a shortcut retrieval function:
[`mds_cadunico()`](https://strategicprojects.github.io/misocial/reference/mds_cadunico.md),
[`mds_bolsa_familia()`](https://strategicprojects.github.io/misocial/reference/mds_bolsa_familia.md),
[`mds_bpc_suas()`](https://strategicprojects.github.io/misocial/reference/mds_bpc_suas.md),
[`mds_suas_rede()`](https://strategicprojects.github.io/misocial/reference/mds_suas_rede.md),
[`mds_suas_financiamento()`](https://strategicprojects.github.io/misocial/reference/mds_suas_financiamento.md),
[`mds_pbf_condicionalidades()`](https://strategicprojects.github.io/misocial/reference/mds_pbf_condicionalidades.md)
and
[`mds_seguranca_alimentar()`](https://strategicprojects.github.io/misocial/reference/mds_seguranca_alimentar.md).

## Usage

``` r
mds_themes()
```

## Value

A tibble with columns `theme`, `name`, `description` and `n_fields`.

## Examples

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
