# Curated field dictionary for the three themes covered by the package
# (inst/extdata/dictionary.csv).
#
# The API publishes no data dictionary: every field name in it was checked
# to have values in the live API (data-raw/check_dictionary.R) and the labels
# are a Portuguese reading of each technical name. Units follow the suffix
# (`_i` count, `_f` currency, `_d` percentage) and what is counted.
#
# Note on Bolsa Familia: `pbf_qtd_familias_benef_i` is *not* the headline
# beneficiary count (Recife, 02/2024: 9,847 against 146,737 in
# `qtd_familias_beneficiarias_bolsa_familia_i`). Its meaning is not
# documented, so it is left out of the curated set; it can still be
# requested by name in mds_data().
#
# Also left out: `pbf_qtd_familias_quilombolas_benef_i` and
# `pbf_qtd_familias_sit_rua_benef_i` carry the same value in every
# municipality-month (PE 2020-2026: 14,615 of 14,615 pairs; Brazil 09/2025:
# 5,570 of 5,570, both summing 283,923), and Recife shows 1 family living on
# the street. One of the two series is a copy of the other; neither can be
# trusted until the source fixes it.
#
# Note on Cadastro Unico income brackets: they are disjoint and add up.
# Brazil, 08/2025 (sum over municipalities, families):
#   pobreza 19,452,231 + baixa renda 7,828,004 = ate 1/2 SM 27,280,235
#   ate 1/2 SM 27,280,235 + acima 1/2 SM 13,816,544 = total 41,096,779
# so "baixa renda" here is the bracket *between* the poverty line and half a
# minimum wage, not "up to half a minimum wage".
#
# Checks behind the themes added in 0.2.0 (Recife 2026 and Pernambuco sums):
# - FNAS transfers: components add up to the total (PE, 06/2026:
#   7,625,605 including "fundo a fundo"; 09/2026: 11,684,831). Account
#   balances (PE, 05/2026) do not add up to their general total.
# - IGD-M: value without incentives + incentives = value with incentives
#   (PE, 08/2026: 4,272,517.4 + 570,828.2 = 4,843,345.6).
# - SICON education, ages 4-17: followed + without information = profile
#   (Recife, 07/2026: 110,464 + 16,896 = 127,360). Health: children +
#   women = people, both for profile and followed.
# - Repercussions: warning + block + suspension + cancellation = total, for
#   both BF and BVA (Recife, 09/2026: 1,589 and 1,192). BF is the family
#   benefit and BVA the benefit of the adolescent aged 16-17 (MDS, Informe
#   Bolsa Familia 44, 16/05/2024). External check: Brazil 03/2024 equals
#   Informe 37 (BF 201,726 / 80,543 / 64,915; BVA 74,853 / 40,474 / 50,015)
#   and 05/2024 equals the state table of Informe 44 (BF 230,466 / 44,247 /
#   36,851).
# - Fomento Rural: women + men responsible = families = sum by group
#   (PE, 09/2026: 85). Cisterns: consumption + production + school = total,
#   and the total only grows over time (cumulative).
# - Components that stopped being published are left out: FNAS "gestao
#   SUAS" (last value 12/2022), PSE media/alta (12/2011), PAB (03/2023).
#
# The dictionary and the theme table live in inst/extdata/*.csv (UTF-8), so
# that the R code stays ASCII and the Python sibling reads the same files.
# They are loaded into the namespace by .onLoad().
mds_dictionary <- NULL
mds_theme_table <- NULL

#' Read a CSV shipped in inst/extdata as a character tibble
#' @noRd
read_extdata <- function(name) {
  path <- system.file("extdata", name, package = "misocialr", mustWork = TRUE)
  tibble::as_tibble(utils::read.csv(path, encoding = "UTF-8",
                                    colClasses = "character"))
}

#' List the themes covered by the package
#'
#' Each theme groups a curated set of MI Social fields (see [mds_fields()])
#' and has a shortcut retrieval function: [mds_cadunico()],
#' [mds_bolsa_familia()], [mds_bpc_suas()], [mds_suas_rede()],
#' [mds_suas_financiamento()], [mds_pbf_condicionalidades()] and
#' [mds_seguranca_alimentar()].
#'
#' @return A tibble with columns `theme`, `name`, `description` and
#'   `n_fields`.
#'
#' @examples
#' mds_themes()
#'
#' @export
mds_themes <- function() {
  n <- table(mds_dictionary$theme)
  dplyr::mutate(
    mds_theme_table,
    n_fields = as.integer(n[.data$theme])
  )
}

#' List curated fields
#'
#' Returns the curated dictionary of MI Social fields: the technical field
#' name used by the API, a readable Portuguese label, the unit and how the
#' value is stored in the API.
#'
#' The API itself has no data dictionary. Labels are a reading of the
#' technical names, checked against the published values; units are what
#' is counted (`Famílias`, `Pessoas`, `R$`, `%`...). `storage_type` is the
#' Solr type given by the suffix (`_i` integer, `_l` long, `_f` float,
#' `_d` double, `_s` string) and says nothing about the unit. Any other
#' field published by the API (see [mds_api_fields()]) can still be
#' requested by name in [mds_data()].
#'
#' `nature` says how a field may be aggregated:
#'
#' | `nature` | Across municipalities | Across months |
#' |---|---|---|
#' | `estoque` (count at the month) | sum | do not sum |
#' | `fluxo` (amount in the month) | sum | sum |
#' | `fluxo anual` (one value a year, in December) | sum | one value a year |
#' | `acumulado` (running total) | sum | do not sum |
#' | `taxa`, `média`, `índice` | do not sum | do not sum |
#'
#' `nature_basis` says where the classification comes from: `medido` (the
#' monthly series was inspected: a running total only grows, an amount of
#' the month varies and restarts), `mesmo grupo de um campo medido`, or
#' `rótulo e unidade` (inferred from the label and unit, not inspected).
#'
#' @param theme Optional theme id (see [mds_themes()]). `NULL` (default)
#'   returns all themes.
#'
#' @return A tibble with columns `theme`, `field`, `label`, `unit`,
#'   `nature`, `nature_basis` and `storage_type`.
#'
#' @examples
#' mds_fields("bpc_suas")
#'
#' @export
mds_fields <- function(theme = NULL) {
  out <- mds_dictionary
  if (!is.null(theme)) {
    validate_theme(theme)
    out <- out[out$theme %in% theme, ]
  }
  dplyr::mutate(out, storage_type = storage_from_suffix(.data$field))
}

#' List the fields published for one municipality
#'
#' Fetches the full documents of one municipality over all months (paging
#' through the whole history) and returns the union of the field names
#' found, with the first and last period in which each field appears. MI
#' Social documents are sparse (a field only exists in the months it was
#' published), which is why the whole history is scanned rather than a
#' single document.
#'
#' This is the catalogue of **one** municipality, not of the whole API:
#' fields that exist only elsewhere (a regional CREAS, for instance) do not
#' appear. Scan other municipalities to widen the search.
#'
#' Results are cached for the session.
#'
#' @param locality 6- or 7-digit IBGE code of the municipality whose
#'   history is scanned. Defaults to Recife (`261160`).
#' @param refresh Logical. Ignore the cached result and ask the API again?
#'   Default `FALSE`.
#'
#' @return A tibble with columns `field`, `unit` (inferred from the
#'   suffix; `"unknown"` when the suffix does not say), `storage_type`,
#'   `in_dictionary`, `first_period` and `last_period`. Empty, with a
#'   warning, when the API has no document for the municipality.
#'
#' @examplesIf interactive()
#' mds_api_fields()
#'
#' @export
mds_api_fields <- function(locality = 261160, refresh = FALSE) {
  check_flag(refresh, "refresh")
  code <- normalize_municipality(locality)
  key <- paste0("api_fields_", code)
  cached <- cache_get(key, refresh)
  if (!is.null(cached)) return(cached)

  docs <- fetch_all_pages(
    list(fq = paste0("codigo_ibge:", code), fl = "*", sort = "id asc"),
    .label = "field list"
  )

  if (length(docs) == 0) {
    cli::cli_warn(
      "The MI Social API has no document for municipality {.val {code}}.",
      class = "misocialr_warning_missing", call = NULL
    )
    return(tibble::tibble(
      field = character(), unit = character(), storage_type = character(),
      in_dictionary = logical(), first_period = character(),
      last_period = character()
    ))
  }

  long <- lapply(docs, function(d) {
    tibble::tibble(field = names(d), period = d$anomes_s %||% NA_character_)
  }) |>
    purrr::list_rbind()

  out <- long |>
    dplyr::filter(!.data$field %in% c("id", mds_id_fields, "_version_")) |>
    dplyr::summarise(
      first_period = min(.data$period),
      last_period  = max(.data$period),
      .by = "field"
    ) |>
    dplyr::mutate(
      unit = unit_from_suffix(.data$field),
      storage_type = storage_from_suffix(.data$field),
      in_dictionary = .data$field %in% mds_dictionary$field,
      .after = "field"
    ) |>
    dplyr::arrange(.data$field)

  cache_set(key, out)
}
