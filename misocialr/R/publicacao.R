#' Drop (or flag) months that were not published yet
#'
#' The MI Social API answers `0`, not "missing", for months whose data has
#' not been published: the BPC series, for example, carries zeros for every
#' municipality up to December of the current year. Treating those zeros as
#' real would make the latest months look like a collapse of the programme.
#'
#' This helper applies an explicit rule, per field:
#'
#' 1. months after the current month are **future**;
#' 2. months after the last month with a non-zero value are
#'    **unpublished**;
#' 3. a field with no non-zero value at all is unpublished entirely.
#'
#' The "last month with a non-zero value" comes from `reference`:
#'
#' - `"selection"` (default): the localities in `data`. Needs no request,
#'   but a small selection can legitimately end in zeros (a municipality
#'   without a CREAS unit, for example), and those zeros would be dropped.
#' - `"brazil"`: every municipality in the country, through
#'   [mds_periods()] (two facet requests per field when not cached). A
#'   month is unpublished only when no municipality in Brazil has a
#'   non-zero value, which keeps legitimate zeros of small selections.
#'
#' A non-zero value in `data` is never classified as unpublished. If the
#' national reference says a month with such a value is unpublished (a
#' cached reference older than the data, for instance), the reference is
#' requested again; if the contradiction remains, the month is kept and a
#' warning is raised.
#'
#' This is an inference from the published values, not an official
#' publication date. A series can legitimately end in zeros, even
#' nationally; use `action = "flag"` to inspect the classification before
#' removing anything.
#'
#' Rows with a missing `value` are never classified as zero: they are kept
#' and flagged as `"missing"`.
#'
#' @param data A tibble returned by [mds_data()] or a theme shortcut.
#' @param today Reference date for rule 1. Default [Sys.Date()].
#' @param reference Where the last published month is read from:
#'   `"selection"` or `"brazil"`. See Details.
#' @param action `"drop"` (default) removes future and unpublished rows;
#'   `"flag"` keeps every row and adds the columns `publication_status`
#'   (`"published"`, `"future"`, `"unpublished"` or `"missing"`),
#'   `publication_reason` and `publication_reference`.
#'
#' @return `data` without the dropped rows, or with the classification
#'   columns. A message summarizes what was removed.
#'
#' @examples
#' x <- tibble::tibble(
#'   locality_id = "261160", period = c("202506", "202507", "202508"),
#'   field = "bpc_ben_i", value = c(98000, 98500, 0)
#' )
#' mds_drop_unpublished(x, today = as.Date("2025-12-01"))
#' mds_drop_unpublished(x, today = as.Date("2025-12-01"), action = "flag")
#'
#' @export
mds_drop_unpublished <- function(data, today = Sys.Date(),
                                 reference = c("selection", "brazil"),
                                 action = c("drop", "flag")) {
  reference <- match.arg(reference)
  action <- match.arg(action)
  input <- normalize_published_input(data, today)
  if (nrow(data) == 0) {
    # Same columns as a non-empty result, so later steps do not depend on
    # whether the query had data.
    if (action == "flag") {
      data$publication_status <- character()
      data$publication_reason <- character()
      data$publication_reference <- character()
    }
    return(data)
  }

  per <- input$period
  field <- input$field
  value <- data$value
  now <- as.integer(format(input$today, "%Y%m"))

  future <- per > now
  known <- !is.na(value)
  nonzero <- known & value != 0 & !future

  sel <- last_nonzero(field[nonzero], per[nonzero])
  last <- if (reference == "brazil") {
    last_published_brazil(unique(field[!future]), sel)
  } else {
    sel
  }

  lim <- last[match(field, names(last))]
  unpublished <- !future & known & (is.na(lim) | per > lim)

  status <- ifelse(future, "future",
                   ifelse(!known, "missing",
                          ifelse(unpublished, "unpublished", "published")))
  reason <- dplyr::case_when(
    status == "future" ~ "month after today",
    status == "missing" ~ "value is missing",
    status == "unpublished" & is.na(lim) ~ "no non-zero value in the reference",
    status == "unpublished" ~ paste0("after the last non-zero month (",
                                     lim, ")"),
    TRUE ~ NA_character_
  )

  if (action == "flag") {
    data$publication_status <- status
    data$publication_reason <- reason
    data$publication_reference <- reference
    return(data)
  }

  report_dropped(field, per, future, unpublished, reference)
  data[!(future | unpublished), ]
}

#' Normalize and check the inputs of mds_drop_unpublished()
#'
#' The period is turned into one integer representation used by every
#' calculation (a factor would otherwise be read by its internal codes) and
#' checked as a real month, 01 to 12.
#' @noRd
normalize_published_input <- function(data, today) {
  needed <- c("period", "field", "value")
  missing_cols <- setdiff(needed, names(data))
  if (length(missing_cols) > 0) {
    abort_mds(c(
      "{.arg data} must have columns {.val {needed}}.",
      "x" = "Missing: {.val {missing_cols}}."
    ), "validation")
  }

  # A date-time is read as its (local) date, as in the Python package.
  if (inherits(today, "POSIXt")) today <- as.Date(today, tz = "")
  if (length(today) != 1 || is.na(today) || !inherits(today, "Date")) {
    abort_mds("{.arg today} must be a single date.", "validation")
  }

  # Element by element (format() on a vector would pad every value to the
  # decimals of the widest one); a factor is read by its labels.
  period <- whole_text(data$period)
  bad <- unique(period[!is_month(period)])
  if (length(bad) > 0) {
    abort_mds(c(
      "!" = "{.field period} must be {.val YYYYMM} (month 01 to 12) with no
             missing values.",
      "x" = "Got {.val {utils::head(bad, 3)}}."
    ), "validation")
  }

  field <- as.character(data$field)
  if (anyNA(field) || any(field == "")) {
    abort_mds("{.field field} must have no missing or empty values.",
              "validation")
  }

  if (!is.numeric(data$value)) {
    abort_mds("{.field value} must be numeric.", "validation")
  }
  if (any(is.infinite(data$value))) {
    abort_mds("{.field value} must not have infinite values.", "validation")
  }

  list(period = as.integer(period), field = field, today = today)
}

#' Last month with a non-zero value, per field
#' @noRd
last_nonzero <- function(field, period) {
  if (length(field) == 0) return(stats::setNames(integer(), character()))
  x <- tapply(period, field, max)
  stats::setNames(as.integer(x), names(x))
}

#' Last month with a non-zero value, per field, in the whole country
#'
#' A reference that calls unpublished a month in which `data` has a non-zero
#' value contradicts the data: it is requested again, and if the
#' contradiction remains the month is kept (the reference is moved to the
#' last month of the data) with a warning.
#' @noRd
last_published_brazil <- function(fields, selection) {
  read <- function(f, refresh) {
    p <- mds_periods(f, refresh = refresh)
    pub <- p$period[p$n_nonzero > 0]
    if (length(pub) == 0) NA_integer_ else max(as.integer(pub))
  }
  last <- vapply(fields, read, integer(1), refresh = FALSE)
  sel <- selection[fields]
  ahead <- !is.na(sel) & (is.na(last) | sel > last)
  if (any(ahead)) {
    last[ahead] <- vapply(fields[ahead], read, integer(1), refresh = TRUE)
    still <- !is.na(sel) & (is.na(last) | sel > last)
    if (any(still)) {
      cli::cli_warn(c(
        "The national reference contradicts the data for
         {.field {fields[still]}}.",
        "i" = "Months with non-zero values were kept."
      ), class = "misocialr_warning_contradiction", call = NULL)
      last[still] <- sel[still]
    }
  }
  stats::setNames(last, fields)
}

#' @noRd
report_dropped <- function(field, period, future, unpublished, reference) {
  n_future <- sum(future)
  if (n_future > 0) {
    cli::cli_inform("Dropped {n_future} row{?s} of future months.")
  }
  if (any(unpublished)) {
    detail <- tibble::tibble(field = field[unpublished],
                             period = period[unpublished]) |>
      dplyr::distinct() |>
      dplyr::summarise(months = paste(sort(.data$period), collapse = ", "),
                       .by = "field")
    what <- if (reference == "brazil") {
      "after the last month published in Brazil"
    } else {
      "of trailing all-zero months"
    }
    cli::cli_inform(c(
      paste0("Dropped {sum(unpublished)} row{?s} ", what, ":"),
      stats::setNames(paste0(detail$field, ": ", detail$months),
                      rep("*", nrow(detail)))
    ))
  }
  invisible()
}
