# First year accepted in `periods` (the API starts in 01/2003).
mds_min_year <- 2000L

#' List the periods available for a field
#'
#' Uses Solr facets to count, for each month, how many municipalities have
#' a value for the field and how many of those values are non-zero.
#'
#' The second count matters: the API returns `0` for months that have not
#' been published yet (for instance, the BPC series carries zeros for every
#' municipality up to the end of the current year). A month where
#' `n_nonzero` is 0 for the whole selection is almost always unpublished,
#' not a true zero. See [mds_drop_unpublished()].
#'
#' Results are cached for the session. Large selections are counted in
#' blocks of at most 200 municipality codes (the same split as
#' [mds_data()]); the blocks do not overlap, so their counts are summed.
#'
#' @param field A single field name (see [mds_fields()]).
#' @param localities Localities to restrict the count to; same forms as in
#'   [mds_data()]. Default `"BR"`.
#' @param refresh Logical. Ignore the cached result and ask the API again?
#'   Default `FALSE`.
#'
#' @return A tibble with columns `period` (`"YYYYMM"`), `n_localities` and
#'   `n_nonzero`, ordered by period. The time of the request is kept in
#'   `attr(x, "retrieved_at")`.
#'
#' @examplesIf interactive()
#' mds_periods("bpc_ben_i", localities = "PE")
#'
#' @export
mds_periods <- function(field, localities = "BR", refresh = FALSE) {
  if (!is.character(field) || length(field) != 1 || is.na(field)) {
    abort_mds("{.arg field} must be a single field name.", "validation")
  }
  check_flag(refresh, "refresh")
  loc <- parse_localities(localities)
  validate_fields(field)

  key <- paste("periods", field, locality_key(loc), sep = "|")
  cached <- cache_get(key, refresh)
  if (!is.null(cached)) return(cached)

  filters <- locality_filters(loc)
  if (length(filters) == 0) filters <- list(NULL)
  has <- solr_has(field)
  nonzero_fq <- paste0(has, " AND -", field, ":0")

  read_pair <- function() {
    all_vals <- sum_facets(lapply(filters, function(lf) {
      facet_periods(c(has, lf), .label = "periods")
    }))
    nonzero <- sum_facets(lapply(filters, function(lf) {
      facet_periods(c(nonzero_fq, lf), .label = "non-zero periods")
    }))
    dplyr::full_join(
      dplyr::rename(all_vals, n_localities = "n"),
      dplyr::rename(nonzero, n_nonzero = "n"),
      by = "period"
    ) |>
      dplyr::mutate(n_nonzero = dplyr::coalesce(.data$n_nonzero, 0L)) |>
      dplyr::arrange(.data$period)
  }

  # The two facets are separate requests and the source can change between
  # them: a month with more non-zero values than values (or non-zero values
  # in a month without values) is read again once, then an error.
  out <- read_pair()
  if (!facets_agree(out)) out <- read_pair()
  if (!facets_agree(out)) {
    abort_mds(c(
      "The two period counts of the MI Social API disagree.",
      "x" = "More non-zero values than values in
             {.val {utils::head(out$period[!agree_rows(out)], 3)}} for
             {.field {field}}.",
      "i" = "The source may be updating; run the query again later."
    ), "response")
  }

  # Only reached when every facet response passed check_response() and the
  # two counts agree.
  cache_set(key, out)
}

#' @noRd
agree_rows <- function(out) {
  !is.na(out$n_localities) & out$n_nonzero <= out$n_localities
}

#' @noRd
facets_agree <- function(out) all(agree_rows(out))

#' Count documents per month for a set of filter queries
#' @noRd
facet_periods <- function(fq, .label) {
  res <- mds_request(
    query = list(
      fq = fq, rows = 0,
      facet = "true", facet.field = "anomes_s",
      facet.limit = -1, facet.mincount = 1, facet.sort = "index"
    ),
    .label = .label
  )
  check_response(res, kind = "facet")
  parse_facet(res$facet_counts$facet_fields$anomes_s)
}

#' Add month counts of disjoint blocks
#' @noRd
sum_facets <- function(parts) {
  x <- purrr::list_rbind(parts)
  if (nrow(x) == 0) return(tibble::tibble(period = character(), n = integer()))
  x |>
    dplyr::summarise(n = sum(.data$n), .by = "period") |>
    dplyr::arrange(.data$period)
}

#' Turn a Solr facet list (`["a", 1, "b", 2]`) into a tibble
#' @noRd
parse_facet <- function(x) {
  if (length(x) == 0) {
    return(tibble::tibble(period = character(), n = integer()))
  }
  idx <- seq(1, length(x), by = 2)
  tibble::tibble(
    period = as.character(unlist(x[idx])),
    n      = as.integer(unlist(x[idx + 1]))
  )
}

#' Normalize the `periods` argument to a vector of `"YYYYMM"` strings
#'
#' Accepted forms:
#' - `NULL` -> the last 12 months up to the current month
#' - a negative integer `-n` -> the last `n` months up to the current month
#' - 4-digit years (`2024`) -> the 12 months of each year
#' - 6-digit months (`202401`, `"202401"`), possibly mixed with years
#' @noRd
parse_periods <- function(periods) {
  if (is.null(periods)) periods <- -12

  if (length(periods) == 0 || anyNA(periods)) {
    abort_mds(c(
      "{.arg periods} must have at least one value and no missing values.",
      "i" = "Use {.val 2024}, {.val 202401} or {.val {-12}}."
    ), "validation")
  }

  if (is.numeric(periods)) {
    bad <- periods[!is.finite(periods) | periods != round(periods)]
    if (length(bad) > 0) {
      abort_mds(c(
        "!" = "Numeric {.arg periods} must be whole numbers.",
        "x" = "Got {.val {bad}}."
      ), "validation")
    }
    if (any(periods < 0)) {
      if (length(periods) != 1) {
        abort_mds(
          "A negative {.arg periods} (last n months) must be used alone.",
          "validation"
        )
      }
      return(last_months(as.integer(-periods)))
    }
    periods <- format(periods, scientific = FALSE, trim = TRUE)
  }

  x <- trimws(as.character(periods))
  # The API starts in 01/2003; a year outside 2000 to next year is a typo,
  # not a query.
  max_year <- as.integer(format(Sys.Date(), "%Y")) + 1L
  year <- suppressWarnings(as.integer(substr(x, 1, 4)))
  in_range <- !is.na(year) & year >= mds_min_year & year <= max_year
  is_year  <- grepl("^[0-9]{4}$", x) & in_range
  is_month <- is_month(x) & in_range
  invalid <- x[!is_year & !is_month]

  if (length(invalid) > 0) {
    abort_mds(c(
      "!" = "Invalid period(s): {.val {invalid}}.",
      "i" = "Use years ({mds_min_year} to {max_year}), months as YYYYMM
             ({.val 202401}) or a negative number for the last n months
             ({.val {-12}})."
    ), "validation")
  }

  years <- x[is_year]
  expanded <- as.vector(outer(years, sprintf("%02d", 1:12), paste0))
  sort(unique(c(x[is_month], expanded)))
}

#' Last `n` months up to the current month, as `"YYYYMM"`
#' @noRd
last_months <- function(n, today = Sys.Date()) {
  first <- as.Date(format(today, "%Y-%m-01"))
  months <- seq(first, by = "-1 month", length.out = n)
  sort(format(months, "%Y%m"))
}
