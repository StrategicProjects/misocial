# In-memory cache (per session): localities, field lists, period facets and
# fields already confirmed to exist. Only complete, validated responses are
# stored (see check_response()).
.misocialr_cache <- new.env(parent = emptyenv())

#' Clear the session cache
#'
#' Removes all cached localities, field lists, periods and field checks,
#' forcing fresh API calls on subsequent requests. To refresh a single
#' result, use the `refresh` argument of [mds_periods()],
#' [mds_localities()] or [mds_api_fields()].
#'
#' @return No return value, called for side effects.
#'
#' @examples
#' mds_clear_cache()
#'
#' @export
mds_clear_cache <- function() {
  rm(list = ls(envir = .misocialr_cache, all.names = TRUE),
     envir = .misocialr_cache)
  cli::cli_alert_success("MI Social cache cleared.")
  invisible()
}

#' Read a cached value, unless a refresh is requested or it is too old
#'
#' `options(misocialr.cache_ttl = seconds)` sets how long a cached result
#' is used; the default (`Inf`) keeps it for the whole session.
#' @noRd
cache_get <- function(key, refresh = FALSE) {
  if (isTRUE(refresh)) return(NULL)
  value <- .misocialr_cache[[key]]
  if (is.null(value)) return(NULL)
  ttl <- getOption("misocialr.cache_ttl", Inf)
  if (!is.numeric(ttl) || length(ttl) != 1 || is.na(ttl) || ttl < 0) {
    abort_mds("{.code misocialr.cache_ttl} must be a non-negative number of
               seconds.", "validation")
  }
  age <- as.numeric(difftime(Sys.time(), attr(value, "retrieved_at"),
                             units = "secs"))
  if (age > ttl) return(NULL)
  value
}

#' Store a value with the time it was obtained
#' @noRd
cache_set <- function(key, value) {
  attr(value, "retrieved_at") <- Sys.time()
  .misocialr_cache[[key]] <- value
  value
}

#' Canonical cache key for a parsed locality selection
#'
#' `c("PE", "PB")` and `c("PB", "PE")` are the same selection and share the
#' cached result.
#' @noRd
locality_key <- function(loc) {
  paste0("uf=", paste(sort(loc$states), collapse = ","),
         ";mun=", paste(sort(loc$municipalities), collapse = ","))
}

#' A single TRUE or FALSE
#' @noRd
check_flag <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1 || is.na(x)) {
    abort_mds("{.arg {arg}} must be a single {.val TRUE} or {.val FALSE}.",
              "validation")
  }
  invisible(TRUE)
}

#' Validate theme ids against the curated dictionary
#' @noRd
validate_theme <- function(theme) {
  valid <- mds_theme_table$theme
  invalid <- setdiff(theme, valid)
  if (length(invalid) > 0) {
    abort_mds(c(
      "!" = "Unknown theme(s): {.val {invalid}}.",
      "i" = "Available themes: {.val {valid}}."
    ), "validation")
  }
  invisible(TRUE)
}

#' Local checks of field names (no request)
#'
#' Run even with `validate = FALSE`: a non-character, empty or malformed
#' name, or an identification field, is an error before anything is sent.
#' @noRd
check_field_names <- function(fields) {
  if (!is.character(fields) || length(fields) == 0 || anyNA(fields)) {
    abort_mds(c(
      "{.arg fields} must be a non-empty character vector of field names.",
      "i" = "See {.fn mds_fields} for the curated list."
    ), "validation")
  }
  bad <- fields[!grepl("^[A-Za-z0-9_]+$", fields)]
  if (length(bad) > 0) {
    abort_mds(c(
      "!" = "Invalid field name(s): {.val {bad}}.",
      "i" = "Field names have only letters, digits and underscores."
    ), "validation")
  }
  id_asked <- intersect(fields, c("id", mds_id_fields))
  if (length(id_asked) > 0) {
    abort_mds(c(
      "!" = "{.val {id_asked}} identif{?ies/y} the document and is not a
             measure.",
      "i" = "Locality and period are always returned as columns."
    ), "validation")
  }
  fields
}

#' Validate field names, locally and against the API
#'
#' Fields in the curated dictionary are accepted without a request. Any other
#' name is checked against the API once per session. `fl` silently ignores
#' unknown names, so without this check a typo would just return an empty
#' result.
#' @noRd
validate_fields <- function(fields) {
  check_field_names(fields)

  known <- c(mds_dictionary$field, .misocialr_cache$valid_fields)
  unknown <- setdiff(fields, known)

  invalid <- character()
  for (f in unknown) {
    ok <- field_exists(f)
    if (ok) {
      .misocialr_cache$valid_fields <- c(.misocialr_cache$valid_fields, f)
    } else {
      invalid <- c(invalid, f)
    }
  }

  if (length(invalid) > 0) {
    abort_mds(c(
      "!" = "Field(s) {.val {invalid}} not found in the MI Social API.",
      "i" = "See {.fn mds_fields} (curated) or {.fn mds_api_fields} (all)."
    ), "validation")
  }

  invisible(TRUE)
}

#' Ask the API whether a field has any value
#'
#' "Defined" is not enough: the Solr schema has dynamic fields (`*_i`,
#' `*_f`, ...), so any name with a type suffix is accepted, even a typo. A
#' field exists when at least one document carries it. Names that match no
#' dynamic pattern are rejected with HTTP 400 (`"undefined field ..."`).
#' @noRd
field_exists <- function(field) {
  res <- tryCatch(
    mds_request(query = list(fq = solr_has(field), rows = 0),
                .label = paste("field check", field)),
    misocialr_error_http = function(e) e
  )
  if (inherits(res, "misocialr_error_http")) {
    if (grepl("undefined field", conditionMessage(res), fixed = TRUE)) {
      return(FALSE)
    }
    # Network or server failure: re-raise instead of reporting a bad field.
    rlang::cnd_signal(res)
  }
  check_response(res, kind = "count")
  res$response$numFound > 0
}
