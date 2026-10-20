# Response contract, paging, document identity and conflict detection.
#
# Every response is checked before it is interpreted or cached: a partial,
# truncated or malformed answer is an error, never an empty result (deep
# review of 0.2.1, items B1, B2, B4, B5, B8 and M5).

#' Raise a classed misocialr error
#'
#' Classes: `misocialr_error_validation` (bad input),
#' `misocialr_error_response` (incomplete or malformed API answer),
#' `misocialr_error_conflict` (the API contradicts itself) and
#' `misocialr_error_http` (transport). All inherit from `misocialr_error`.
#' @noRd
abort_mds <- function(message, kind, ..., parent = NULL,
                      .envir = parent.frame()) {
  cli::cli_abort(
    message,
    class = c(paste0("misocialr_error_", kind), "misocialr_error"),
    ...,
    parent = parent, call = NULL, .envir = .envir
  )
}

#' Check the shape of a Solr response before using it
#'
#' @param kind `"docs"` (a page of documents), `"count"` (`rows = 0`, only
#'   `numFound` is used) or `"facet"` (month counts in `facet_counts`).
#' @noRd
check_response <- function(res, start = 0L,
                           kind = c("docs", "count", "facet")) {
  kind <- match.arg(kind)
  where <- kind
  if (kind == "docs") where <- paste0("page after ", start, " documents")

  if (!is.list(res) || !is.list(res$response)) {
    abort_mds(c(
      "Unexpected response from the MI Social API.",
      "x" = "No {.field response} element ({where})."
    ), "response")
  }
  status <- res$responseHeader$status
  if (!is.null(status) && !identical(as.integer(status), 0L)) {
    abort_mds(c(
      "The MI Social API reported an error.",
      "x" = "responseHeader status {.val {status}} ({where})."
    ), "response")
  }
  # Solr flags results cut short by a time limit.
  if (isTRUE(res$responseHeader$partialResults)) {
    abort_mds(c(
      "Partial results from the MI Social API.",
      "x" = "The server stopped the query before the end ({where}). Try a
             smaller selection."
    ), "response")
  }

  n <- res$response$numFound
  if (!is_count(n)) {
    abort_mds(c(
      "Unexpected response from the MI Social API.",
      "x" = "{.field numFound} must be a non-negative whole number ({where})."
    ), "response")
  }

  if (kind == "docs") check_docs_shape(res$response$docs, where)
  if (kind == "facet") check_facet_shape(res, where)
  invisible(TRUE)
}

#' A month as YYYYMM with the month between 01 and 12 (the one calendar rule
#' used for input, documents and facets)
#' @noRd
is_month <- function(x) {
  x <- as.character(x)
  ok <- !is.na(x) & grepl("^[0-9]{6}$", x)
  ok[ok] <- as.integer(substr(x[ok], 5, 6)) %in% 1:12
  ok
}

#' @noRd
is_count <- function(x) {
  is.numeric(x) && length(x) == 1 && !is.na(x) && is.finite(x) &&
    x >= 0 && x == round(x)
}

#' @noRd
check_docs_shape <- function(docs, where) {
  ok <- is.list(docs) && is.null(names(docs)) &&
    all(vapply(docs, function(d) is.list(d) && !is.null(names(d)),
               logical(1)))
  if (!ok) {
    abort_mds(c(
      "Unexpected response from the MI Social API.",
      "x" = "{.field docs} must be a list of documents ({where})."
    ), "response")
  }
  invisible(TRUE)
}

#' @noRd
check_facet_shape <- function(res, where) {
  f <- res$facet_counts$facet_fields$anomes_s
  # An empty facet (no month has a value) is valid; a missing one is not.
  ok <- is.list(f) && length(f) %% 2 == 0
  if (ok && length(f) > 0) {
    i <- seq(1, length(f), by = 2)
    months <- vapply(f[i], function(x) {
      if (is.character(x) && length(x) == 1) x else NA_character_
    }, character(1))
    ok <- all(is_month(months)) && !anyDuplicated(months) &&
      all(vapply(f[i + 1], is_count, logical(1)))
  }
  if (!ok) {
    abort_mds(c(
      "Unexpected response from the MI Social API.",
      "x" = "Missing or malformed {.field facet_counts} ({where})."
    ), "response")
  }
  invisible(TRUE)
}

#' Page through a Solr query until all documents are read
#'
#' Pages are read with Solr's `cursorMark`, which walks the results by the
#' sort key (`id`) instead of by position: documents added or removed while
#' paging cannot shift the pages. The total (`numFound`) must still stay the
#' same on every page and no document id may repeat; reading stops as soon
#' as `numFound` documents were read, and fewer than that is an error.
#' @noRd
fetch_all_pages <- function(query, .label = "data") {
  # cursorMark requires the sort to include the unique key.
  query$sort <- query$sort %||% "id asc"
  pages <- list()
  cursor <- "*"
  read <- 0L
  total <- NULL
  repeat {
    res <- mds_request(
      query = c(query, list(cursorMark = cursor, rows = mds_page_size)),
      .label = .label
    )
    check_response(res, read, "docs")
    docs <- res$response$docs
    n <- res$response$numFound
    if (is.null(total)) total <- n
    if (n != total) {
      abort_mds(c(
        "The MI Social API changed while it was being read.",
        "x" = "{.field numFound} went from {total} to {n} after {read}
               documents.",
        "i" = "Run the query again."
      ), "response")
    }
    pages[[length(pages) + 1]] <- docs
    read <- read + length(docs)
    if (read > total) {
      abort_mds(c(
        "Unexpected response from the MI Social API.",
        "x" = "{read} documents read, but {.field numFound} is {total}."
      ), "response")
    }
    if (read >= total) break
    nxt <- res$nextCursorMark
    # The cursor stops moving at the end of the results: if that happens
    # before numFound, part of the data is missing.
    if (!is.character(nxt) || length(nxt) != 1 || identical(nxt, cursor) ||
          length(docs) == 0) {
      abort_mds(c(
        "Incomplete response from the MI Social API.",
        "x" = "Read {read} of {total} documents; the next page is missing or
               empty."
      ), "response")
    }
    cursor <- nxt
  }
  docs <- purrr::list_flatten(pages)
  ids <- doc_chr(docs, "id")
  dup <- unique(ids[!is.na(ids) & duplicated(ids)])
  if (length(dup) > 0) {
    abort_mds(c(
      "The MI Social API returned the same document twice.",
      "x" = "Repeated id{?s}: {.val {utils::head(dup, 3)}}.",
      "i" = "The source probably changed while it was being read; run the
             query again."
    ), "response")
  }
  docs
}

#' Check that every data document identifies its municipality and month
#'
#' Without a valid key, documents of different municipalities would share
#' an `NA` id and be merged by the de-duplication.
#' @noRd
check_doc_identity <- function(docs) {
  code <- doc_chr(docs, "codigo_ibge")
  month <- doc_chr(docs, "anomes_s")
  bad <- which(is.na(code) | !grepl("^[0-9]{6}$", code) |
                 !is_month(month))
  if (length(bad) > 0) {
    abort_mds(c(
      "Unexpected document in the MI Social response.",
      "x" = "{length(bad)} document{?s} without a valid {.field codigo_ibge}
             (6 digits) or {.field anomes_s} (YYYYMM, month 01 to 12)."
    ), "response")
  }
  invisible(TRUE)
}

#' One numeric value per document
#'
#' Each document must carry the field as a single number or numeric string
#' (or not at all). A list or a vector is an error: flattening it would
#' shift values between municipalities.
#' @noRd
doc_values <- function(docs, field) {
  raw <- lapply(docs, function(d) d[[field]])
  has <- !vapply(raw, is.null, logical(1))
  scalar <- vapply(raw[has], function(v) is.atomic(v) && length(v) == 1,
                   logical(1))
  if (!all(scalar)) {
    abort_mds(c(
      "!" = "Field {.field {field}} is not a single value per document.",
      "x" = "{sum(!scalar)} document{?s} carry a list or several values."
    ), "response")
  }
  txt <- vapply(raw[has], function(v) as.character(v), character(1))
  value <- suppressWarnings(as.numeric(txt))
  bad <- !is.na(txt) & is.na(value) & !is.nan(value)
  if (any(bad)) {
    abort_mds(c(
      "!" = "Field {.field {field}} is not numeric.",
      "x" = "The API returned {.val {utils::head(unique(txt[bad]), 3)}}.",
      "i" = "misocialr returns numeric values only."
    ), "validation")
  }
  # "NaN", "Inf" or "1e999" are numbers that cannot be a measure; accepting
  # them would create missing or infinite values the source never meant.
  nonfinite <- !is.finite(value)
  if (any(nonfinite)) {
    abort_mds(c(
      "!" = "Field {.field {field}} has non-finite values.",
      "x" = "The API returned {.val {utils::head(unique(txt[nonfinite]), 3)}}."
    ), "response")
  }
  list(has = has, value = value)
}

#' Remove repeated observations, refusing conflicting ones
#'
#' A missing value and a known value for the same key keep the known one.
#'
#' A municipality requested both by code and through its state comes back
#' in two requests with the same value; that repetition is dropped. Two
#' different values for the same municipality, month and field are a
#' contradiction of the source and an error.
#' @noRd
dedupe_observations <- function(out) {
  key <- paste(out$locality_id, out$period, out$field, sep = "\r")
  dup <- duplicated(key) | duplicated(key, fromLast = TRUE)
  if (!any(dup)) return(out)
  # A missing value never replaces a known one, whatever the order of the
  # rows: when a key has a known value, its missing rows are dropped first.
  known_key <- unique(key[dup & !is.na(out$value)])
  drop_na <- dup & is.na(out$value) & key %in% known_key
  out <- out[!drop_na, ]
  key <- key[!drop_na]
  dup <- duplicated(key) | duplicated(key, fromLast = TRUE)
  if (!any(dup)) return(out)
  vals <- tapply(out$value[dup], key[dup], function(v) {
    length(unique(v[!is.na(v)])) <= 1
  })
  conflicts <- names(vals)[!vals]
  if (length(conflicts) > 0) {
    abort_mds(c(
      "The MI Social API returned conflicting values.",
      "x" = "Different values for the same municipality / month / field:
             {.val {gsub('\r', ' / ', utils::head(conflicts, 3))}}."
    ), "conflict")
  }
  out[!duplicated(key), ]
}
