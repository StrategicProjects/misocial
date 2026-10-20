# Package index

## Retrieve data

The main retrieval function and one shortcut per theme.

- [`mds_data()`](https://strategicprojects.github.io/misocial/reference/mds_data.md)
  : Fetch MI Social data
- [`mds_cadunico()`](https://strategicprojects.github.io/misocial/reference/mds_cadunico.md)
  : Cadastro Unico: registered families and people, by income bracket
- [`mds_bolsa_familia()`](https://strategicprojects.github.io/misocial/reference/mds_bolsa_familia.md)
  : Bolsa Familia programme: beneficiary families, benefits and
  transfers
- [`mds_bpc_suas()`](https://strategicprojects.github.io/misocial/reference/mds_bpc_suas.md)
  : BPC and social assistance network (CRAS, CREAS)
- [`mds_suas_rede()`](https://strategicprojects.github.io/misocial/reference/mds_suas_rede.md)
  : Social assistance network (CadSUAS)
- [`mds_suas_financiamento()`](https://strategicprojects.github.io/misocial/reference/mds_suas_financiamento.md)
  : SUAS funding: FNAS transfers, account balances and IGD-M
- [`mds_pbf_condicionalidades()`](https://strategicprojects.github.io/misocial/reference/mds_pbf_condicionalidades.md)
  : Bolsa Familia conditionalities: education and health follow-up
- [`mds_seguranca_alimentar()`](https://strategicprojects.github.io/misocial/reference/mds_seguranca_alimentar.md)
  : Food and nutrition security: PAA, Fomento Rural and cisterns

## Discover themes, fields, periods and localities

The curated dictionary, everything the API has, and what is available
where and when.

- [`mds_themes()`](https://strategicprojects.github.io/misocial/reference/mds_themes.md)
  : List the themes covered by the package
- [`mds_fields()`](https://strategicprojects.github.io/misocial/reference/mds_fields.md)
  : List curated fields
- [`mds_api_fields()`](https://strategicprojects.github.io/misocial/reference/mds_api_fields.md)
  : List the fields published for one municipality
- [`mds_periods()`](https://strategicprojects.github.io/misocial/reference/mds_periods.md)
  : List the periods available for a field
- [`mds_localities()`](https://strategicprojects.github.io/misocial/reference/mds_localities.md)
  : List municipalities available in the API

## Publication status

The API answers 0 for months not yet published; remove or flag them
explicitly.

- [`mds_drop_unpublished()`](https://strategicprojects.github.io/misocial/reference/mds_drop_unpublished.md)
  : Drop (or flag) months that were not published yet

## Utilities

Helpers and cache management.

- [`ibge_code7()`](https://strategicprojects.github.io/misocial/reference/ibge_code7.md)
  : Convert 6-digit MDS municipality codes to 7-digit IBGE codes
- [`mds_clear_cache()`](https://strategicprojects.github.io/misocial/reference/mds_clear_cache.md)
  : Clear the session cache
