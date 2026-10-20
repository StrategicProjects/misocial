# API base URL
mds_base_url <- "https://aplicacoes.mds.gov.br/sagi/servicos/misocial"

# Columns that identify a document (municipality x month). Everything else in
# a document is a measure.
mds_id_fields <- c("codigo_ibge", "municipio", "sigla_uf", "anomes_s")

#' Build and execute a request to the MI Social API
#'
#' The MI Social API is an open Apache Solr `select` handler: every call is a
#' `q=*:*` query narrowed with filter queries (`fq`), with paging (`start`,
#' `rows`), field selection (`fl`) and facets.
#'
#' @param query Named list of query parameters. Repeated parameters (several
#'   `fq`) are given as a character vector under one name.
#' @param .label Friendly label for cli messages
#' @return Parsed JSON response as a list
#' @noRd
mds_request <- function(query = list(), .label = "data") {

  query <- purrr::compact(c(list(q = "*:*", wt = "json"), query))

  quiet <- isTRUE(getOption("misocialr.quiet", FALSE))
  if (!quiet) {
    cli::cli_progress_step("Fetching {(.label)} from MDS MI Social API...")
  }

  req <- httr2::request(mds_base_url) |>
    httr2::req_user_agent(user_agent()) |>
    httr2::req_timeout(getOption("misocialr.timeout", 180)) |>
    httr2::req_retry(
      max_tries = 3,
      backoff = function(i) getOption("misocialr.retry_backoff", 2),
      # Also retry when the connection itself fails (DNS, reset, timeout).
      retry_on_failure = TRUE,
      # 400 means the query itself is wrong (e.g. an undefined field):
      # retrying would only repeat the same answer.
      is_transient = function(resp) {
        httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504)
      },
      # A Retry-After header is obeyed, but never for more than 30 s per
      # try, and the retries never wait more than 120 s in total.
      after = function(resp) {
        wait <- httr2::resp_retry_after(resp)
        if (is.na(wait)) NA else min(wait, 30)
      },
      max_seconds = 120
    ) |>
    # The query goes in the body (POST form): with many months, fields and
    # codes a GET URL passes the server limit (HTTP 414 measured at about
    # 8,000 characters). The Solr select handler answers both the same way.
    httr2::req_body_form(!!!query, .multi = "explode")

  req <- httr2::req_error(
    req,
    is_error = function(resp) httr2::resp_status(resp) >= 400,
    body = function(resp) http_error_hint(resp)
  )

  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      status <- if (inherits(e, "httr2_http")) httr2::resp_status(e$resp)
      abort_mds(c(
        "Failed to access the MDS MI Social API.",
        "x" = conditionMessage(e),
        "i" = "URL: {.url {req$url}} (query sent by POST)"
      ), "http", status = status, parent = e)
    }
  )

  # The server labels its JSON as text/plain. A body that is not JSON (an
  # HTML error page, for instance) is a response error, not a parser error.
  result <- tryCatch(
    httr2::resp_body_json(resp, check_type = FALSE, simplifyVector = FALSE),
    error = function(e) {
      abort_mds(c(
        "Unexpected response from the MI Social API.",
        "x" = "The body is not valid JSON.",
        "i" = "URL: {.url {req$url}}"
      ), "response", parent = e)
    }
  )

  if (!quiet) cli::cli_progress_done()

  result
}

#' User agent with the package version
#' @noRd
user_agent <- function() {
  paste0("misocialr/", utils::packageVersion("misocialr"),
         " (R package; https://aplicacoes.mds.gov.br/sagi/servicos/misocial)")
}

#' Explain an HTTP error from the MI Social API
#'
#' Solr answers invalid queries with HTTP 400 and a JSON body whose
#' `error$msg` says what is wrong (`"undefined field xyz"`). That message is
#' far more useful than the status code, so it is surfaced when present.
#' @noRd
http_error_hint <- function(resp) {
  status <- httr2::resp_status(resp)
  msg <- tryCatch(
    httr2::resp_body_json(resp, check_type = FALSE)$error$msg,
    error = function(e) NULL
  )
  if (!is.null(msg)) return(paste0("HTTP error ", status, ": ", msg))
  paste0("HTTP error ", status)
}

#' Solr disjunction of terms for one field: `field:(a OR b OR c)`
#' @noRd
solr_in <- function(field, values) {
  paste0(field, ":(", paste(values, collapse = " OR "), ")")
}

#' Solr filter matching documents where a field has a value
#' @noRd
solr_has <- function(field) {
  paste0(field, ":[* TO *]")
}

#' Split a vector into chunks of at most `size` elements
#' @noRd
chunk_vector <- function(x, size) {
  if (length(x) == 0) return(list(x))
  split(x, ceiling(seq_along(x) / size))
}

#' Text of a vector; whole numbers are written without decimals or
#' scientific notation (100000 -> "100000", not "1e+05")
#' @noRd
whole_text <- function(x) {
  if (!is.numeric(x)) return(as.character(x))
  ifelse(is.finite(x) & x == round(x), sprintf("%.0f", x), as.character(x))
}

#' One character column from a list of Solr documents
#' @noRd
doc_chr <- function(docs, field) {
  purrr::map_chr(docs, field, .default = NA_character_)
}

#' Unit implied by the field-name suffix
#'
#' MI Social field names end with the Solr dynamic-field type: `_i`/`_l` integer
#' count, `_f` float (currency in most cases), `_d` double (percentages and
#' rates), `_s` string.
#' @noRd
unit_from_suffix <- function(field) {
  # `_s` is how the value is stored (a string), not what it measures: a
  # numeric string such as "98463694.0" has an unknown unit.
  dplyr::case_when(
    endsWith(field, "_i") ~ "count",
    endsWith(field, "_l") ~ "count",
    endsWith(field, "_f") ~ "value",
    endsWith(field, "_d") ~ "rate",
    TRUE                  ~ "unknown"
  )
}

#' Solr storage type implied by the field-name suffix
#' @noRd
storage_from_suffix <- function(field) {
  dplyr::case_when(
    endsWith(field, "_i") ~ "integer",
    endsWith(field, "_l") ~ "long",
    endsWith(field, "_f") ~ "float",
    endsWith(field, "_d") ~ "double",
    endsWith(field, "_s") ~ "string",
    TRUE                  ~ "untyped"
  )
}

#' Current month as YYYYMM integer
#' @noRd
current_period <- function() {
  as.integer(format(Sys.Date(), "%Y%m"))
}
