# Documents per page. A month of all 5,571 municipalities fits in one page;
# a full year of Brazil (~67,000 documents) with a few fields came back in a
# single 21-second request when tested, so 10,000 keeps each page well under
# the timeout.
mds_page_size <- 10000L

# Municipality codes per filter query, to keep URLs at a safe length.
mds_max_codes <- 200L

#' Fetch MI Social data
#'
#' Main retrieval function. Returns monthly municipal values of the
#' requested fields as a tidy long tibble: one row per field x municipality
#' x month in which the API has a value.
#'
#' The query is validated before any data request (field names, period
#' format, locality codes), then paged through Solr and, when many
#' municipality codes are given, split into several requests whose results
#' are bound together.
#'
#' Values are returned as published. Note that the API answers `0` for
#' months that were not published yet; use [mds_drop_unpublished()] to
#' remove those trailing zeros explicitly.
#'
#' @param fields Character vector of field names. See [mds_fields()] for
#'   the curated list and [mds_api_fields()] for everything the API has.
#' @param periods Periods to fetch:
#'   - `NULL` (default): the last 12 months up to the current month;
#'   - a negative number `-n`: the last `n` months up to the current month;
#'   - years (`2024`) and/or months as `YYYYMM` (`202401`, `"202401"`).
#' @param localities `"BR"` (all of Brazil), state abbreviations (`"PE"`)
#'   or 2-digit state codes (`26`), and/or 6- or 7-digit IBGE municipality
#'   codes (`2611606`), in any combination. Default `"BR"`.
#' @param validate Logical. Check that fields not in the dictionary exist
#'   in the API before requesting data? Default `TRUE`. Local checks (names,
#'   periods, localities) always run.
#'
#' @return A tibble with columns `locality_id` (6-digit code used by the
#'   API), `ibge_code` (7-digit IBGE code), `locality_name`, `state`,
#'   `period` (`"YYYYMM"`), `field`, `label`, `unit` and `value` (double).
#'   The time of the request is kept in `attr(x, "retrieved_at")`.
#'
#' @details Only numeric fields are supported: a field whose values are text
#'   (such as `regiao`) is an error rather than an empty result.
#'
#'   Every response is checked before it is used: a partial or malformed
#'   answer, a total that changes while paging, a document read twice, a
#'   document without municipality or month, a field with several values in
#'   one document, or two different values for the same municipality, month
#'   and field are errors (classes `misocialr_error_response` and
#'   `misocialr_error_conflict`). A requested municipality that returns no
#'   document raises a warning.
#'
#'   Options: `misocialr.timeout` (seconds per request, default 180) and
#'   `misocialr.quiet` (`TRUE` hides the progress messages).
#'
#' @examplesIf interactive()
#' mds_data(
#'   c("bpc_ben_i", "cadsuas_qtd_cras_i"),
#'   periods = 2025,
#'   localities = c(2611606, 2607901)
#' )
#'
#' @export
mds_data <- function(fields, periods = NULL, localities = "BR",
                     validate = TRUE) {

  # Local checks always run; `validate` only turns off the remote check of
  # field existence.
  check_flag(validate, "validate")
  fields <- check_field_names(unique(fields))
  months <- parse_periods(periods)
  loc <- parse_localities(localities)
  if (validate) validate_fields(fields)

  plan <- build_query_plan(fields, months, loc)

  # lapply rather than purrr::map: errors reach the user as raised, without
  # the "In index: 1" wrapper.
  docs <- lapply(seq_along(plan), function(i) {
    fetch_all_pages(plan[[i]], .label = request_label(i, length(plan)))
  }) |>
    purrr::list_flatten()

  out <- dedupe_observations(parse_docs(docs, fields))
  warn_missing_municipalities(loc, docs)
  attr(out, "retrieved_at") <- Sys.time()
  out
}

#' Locality filters without overlap
#'
#' States go in one filter; municipality codes are split in groups of
#' `mds_max_codes`. A municipality whose state is also requested is left
#' out, since the state filter already brings it: the requests are disjoint
#' and facet counts can be summed across them.
#' @noRd
locality_filters <- function(loc) {
  mun <- loc$municipalities
  if (length(loc$states) > 0 && length(mun) > 0) {
    uf <- names(mds_states)[match(as.integer(substr(mun, 1, 2)), mds_states)]
    mun <- mun[!uf %in% loc$states]
  }
  c(
    if (length(loc$states) > 0) solr_in("sigla_uf", loc$states),
    if (length(mun) > 0) {
      vapply(chunk_vector(mun, mds_max_codes),
             function(x) solr_in("codigo_ibge", x), character(1))
    }
  )
}

#' One query per locality filter
#'
#' Months are passed as an explicit `OR` list, which also avoids the
#' ambiguity of `anomes_s:2024*` prefixes. The document `id` is requested to
#' detect documents read twice while paging.
#' @noRd
build_query_plan <- function(fields, months, loc) {
  fl <- paste(unique(c("id", mds_id_fields, fields)), collapse = ",")
  month_fq <- solr_in("anomes_s", months)

  loc_filters <- locality_filters(loc)
  if (length(loc_filters) == 0) loc_filters <- list(NULL)

  lapply(loc_filters, function(lf) {
    list(fq = c(month_fq, lf), fl = fl, sort = "id asc")
  })
}

#' Warn about requested municipalities that returned no document
#'
#' A code with a valid check digit may still not exist in the API (999999
#' and its digit, for example); every month carries every municipality, so
#' no document at all means the code is not in the source.
#' @noRd
warn_missing_municipalities <- function(loc, docs) {
  if (length(loc$municipalities) == 0) return(invisible())
  got <- unique(doc_chr(docs, "codigo_ibge"))
  missing <- setdiff(loc$municipalities, got)
  if (length(missing) > 0) {
    cli::cli_warn(c(
      "No document in the MI Social API for municipalit{?y/ies}
       {.val {ibge_code7(missing)}} in the requested months.",
      "i" = "Check the code with {.fn mds_localities}."
    ), class = "misocialr_warning_missing", call = NULL)
  }
  invisible()
}

#' @noRd
request_label <- function(i, n) {
  if (n == 1) "data" else paste0("data (request ", i, "/", n, ")")
}

#' Flatten Solr documents into the long output format
#'
#' Documents are sparse: a field that was not published for a month is
#' absent from that document, so it produces no row. Each document must
#' identify its municipality and month and carry at most one value per
#' field (see `check_doc_identity()` and `doc_values()`).
#' @noRd
parse_docs <- function(docs, fields) {
  if (length(docs) == 0) return(empty_result())
  check_doc_identity(docs)

  id <- tibble::tibble(
    locality_id   = doc_chr(docs, "codigo_ibge"),
    locality_name = doc_chr(docs, "municipio"),
    state         = doc_chr(docs, "sigla_uf"),
    period        = doc_chr(docs, "anomes_s")
  )

  long <- lapply(fields, function(f) {
    v <- doc_values(docs, f)
    dplyr::mutate(id[v$has, ], field = f, value = v$value)
  }) |>
    purrr::list_rbind()

  if (nrow(long) == 0) return(empty_result())

  # A field may belong to more than one theme (CRAS and CREAS are in both
  # bpc_suas and suas_rede); label and unit are the same in every row.
  dict <- dplyr::distinct(mds_dictionary[, c("field", "label", "unit")],
                          .data$field, .keep_all = TRUE)
  long |>
    dplyr::left_join(dict, by = "field") |>
    dplyr::mutate(
      label = dplyr::coalesce(.data$label, .data$field),
      unit  = dplyr::coalesce(.data$unit, unit_from_suffix(.data$field)),
      ibge_code = ibge_code7(.data$locality_id)
    ) |>
    dplyr::select(
      "locality_id", "ibge_code", "locality_name", "state", "period",
      "field", "label", "unit", "value"
    ) |>
    dplyr::arrange(match(.data$field, fields), .data$locality_id, .data$period)
}

#' @noRd
empty_result <- function() {
  tibble::tibble(
    locality_id = character(), ibge_code = character(),
    locality_name = character(), state = character(), period = character(),
    field = character(), label = character(), unit = character(),
    value = double()
  )
}

#' Cadastro Unico: registered families and people, by income bracket
#'
#' Shortcut for [mds_data()] with the curated Cadastro Unico fields
#' (`mds_fields("cadunico")`).
#'
#' @inheritParams mds_data
#' @param fields Fields to fetch. `NULL` (default) fetches every curated
#'   field of the theme.
#'
#' @return A tibble in the format of [mds_data()].
#'
#' @examplesIf interactive()
#' mds_cadunico(periods = 2025, localities = "PE")
#'
#' @export
mds_cadunico <- function(periods = NULL, localities = "BR",
                         fields = NULL) {
  fields <- fields %||% mds_fields("cadunico")$field
  mds_data(fields, periods = periods, localities = localities)
}

#' Bolsa Familia programme: beneficiary families, benefits and transfers
#'
#' Shortcut for [mds_data()] with the curated Bolsa Familia fields
#' (`mds_fields("bolsa_familia")`).
#'
#' @inheritParams mds_cadunico
#'
#' @return A tibble in the format of [mds_data()].
#'
#' @examplesIf interactive()
#' mds_bolsa_familia(periods = -6, localities = 2611606)
#'
#' @export
mds_bolsa_familia <- function(periods = NULL, localities = "BR",
                              fields = NULL) {
  fields <- fields %||% mds_fields("bolsa_familia")$field
  mds_data(fields, periods = periods, localities = localities)
}

#' BPC and social assistance network (CRAS, CREAS)
#'
#' Shortcut for [mds_data()] with the curated BPC and CadSUAS fields
#' (`mds_fields("bpc_suas")`).
#'
#' @inheritParams mds_cadunico
#'
#' @return A tibble in the format of [mds_data()].
#'
#' @examplesIf interactive()
#' mds_bpc_suas(periods = 2025, localities = "PE")
#'
#' @export
mds_bpc_suas <- function(periods = NULL, localities = "BR",
                         fields = NULL) {
  fields <- fields %||% mds_fields("bpc_suas")$field
  mds_data(fields, periods = periods, localities = localities)
}

#' Social assistance network (CadSUAS)
#'
#' Shortcut for [mds_data()] with the curated network fields
#' (`mds_fields("suas_rede")`): CRAS, CREAS, Centro POP, centros de
#' convivencia, centros-dia, unidades de acolhimento, regional CREAS and the
#' professionals registered in each kind of unit (professionals only from
#' 09/2025).
#'
#' @inheritParams mds_cadunico
#'
#' @return A tibble in the format of [mds_data()].
#'
#' @examplesIf interactive()
#' mds_suas_rede(periods = 202609, localities = "PE")
#'
#' @export
mds_suas_rede <- function(periods = NULL, localities = "BR",
                          fields = NULL) {
  fields <- fields %||% mds_fields("suas_rede")$field
  mds_data(fields, periods = periods, localities = localities)
}

#' SUAS funding: FNAS transfers, account balances and IGD-M
#'
#' Shortcut for [mds_data()] with the curated funding fields
#' (`mds_fields("suas_financiamento")`).
#'
#' The transfer components add up to `suas_repasse_mun_vl_total_fundo_f`
#' (checked for Pernambuco in 06/2026 and 09/2026). The account balances do
#' **not** add up to the general total, so they should be read one by one.
#'
#' @inheritParams mds_cadunico
#'
#' @return A tibble in the format of [mds_data()].
#'
#' @examplesIf interactive()
#' mds_suas_financiamento(periods = 2025, localities = 2611606)
#'
#' @export
mds_suas_financiamento <- function(periods = NULL, localities = "BR",
                                   fields = NULL) {
  fields <- fields %||% mds_fields("suas_financiamento")$field
  mds_data(fields, periods = periods, localities = localities)
}

#' Bolsa Familia conditionalities: education and health follow-up
#'
#' Shortcut for [mds_data()] with the curated conditionality fields
#' (`mds_fields("pbf_condicionalidades")`): the SICON series from 2023 on
#' (education, health, warnings, blocks, suspensions and cancellations) and
#' the IGD-M follow-up rates, available since 2015.
#'
#' @inheritParams mds_cadunico
#'
#' @return A tibble in the format of [mds_data()].
#'
#' @examplesIf interactive()
#' mds_pbf_condicionalidades(periods = 2026, localities = "PE")
#'
#' @export
mds_pbf_condicionalidades <- function(periods = NULL, localities = "BR",
                                      fields = NULL) {
  fields <- fields %||% mds_fields("pbf_condicionalidades")$field
  mds_data(fields, periods = periods, localities = localities)
}

#' Food and nutrition security: PAA, Fomento Rural and cisterns
#'
#' Shortcut for [mds_data()] with the curated food security fields
#' (`mds_fields("seguranca_alimentar")`). Cistern counts are cumulative.
#'
#' @inheritParams mds_cadunico
#'
#' @return A tibble in the format of [mds_data()].
#'
#' @examplesIf interactive()
#' mds_seguranca_alimentar(periods = 2025, localities = "PE")
#'
#' @export
mds_seguranca_alimentar <- function(periods = NULL, localities = "BR",
                                    fields = NULL) {
  fields <- fields %||% mds_fields("seguranca_alimentar")$field
  mds_data(fields, periods = periods, localities = localities)
}
