# Cases from the deep review of 0.2.1 (ANALISE_PROFUNDA_MISOCIALR_2026-10-19.md;
# fixes in NEWS.md, 0.3.0).

clear <- function(env = parent.frame()) {
  suppressMessages(mds_clear_cache())
  withr::defer(suppressMessages(mds_clear_cache()), envir = env)
}
facet <- function(...) {
  list(responseHeader = list(status = 0L),
       response = list(numFound = 0L, docs = list()),
       facet_counts = list(facet_fields = list(anomes_s = list(...))))
}

# B1 ------------------------------------------------------------------------
test_that("a partial or facet-less answer is not cached as 'no period'", {
  clear()
  local_mocked_bindings(mds_request = function(...) {
    list(responseHeader = list(partialResults = TRUE),
         response = list(numFound = 0L, docs = list()))
  })
  expect_error(mds_periods("bpc_ben_i"), class = "misocialr_error_response")
  expect_length(ls(.misocialr_cache), 0)

  local_mocked_bindings(mds_request = function(...) {
    list(response = list(numFound = 0L, docs = list()))
  })
  expect_error(mds_periods("bpc_ben_i"), "facet_counts")
  expect_length(ls(.misocialr_cache), 0)
})

test_that("an empty facet is a valid answer and is cached", {
  clear()
  local_mocked_bindings(mds_request = function(...) facet())
  p <- mds_periods("bpc_ben_i")
  expect_identical(nrow(p), 0L)
  expect_true(any(startsWith(ls(.misocialr_cache), "periods|")))
})

# B2 ------------------------------------------------------------------------
test_that("an incomplete municipality list is rejected and not cached", {
  clear()
  recife <- list(id = "a", codigo_ibge = "261160", municipio = "RECIFE",
                 sigla_uf = "PE", regiao = "NORDESTE")
  local_mocked_bindings(mds_request = function(...) {
    list(responseHeader = list(partialResults = TRUE),
         response = list(numFound = 5571L, docs = list(recife)))
  })
  expect_error(mds_localities(), class = "misocialr_error_response")
  expect_length(ls(.misocialr_cache), 0)
})

test_that("the municipality list is paged until numFound", {
  clear()
  local_mocked_bindings(mds_page_size = 1L)
  docs <- list(
    list(id = "a", codigo_ibge = "261160", municipio = "RECIFE",
         sigla_uf = "PE", regiao = "NORDESTE"),
    list(id = "b", codigo_ibge = "260960", municipio = "OLINDA",
         sigla_uf = "PE", regiao = "NORDESTE")
  )
  local_mocked_bindings(mds_request = cursor_server(list(docs[1], docs[2])))
  locs <- mds_localities(period = "202512")
  expect_identical(locs$ibge_code, c("2609600", "2611606"))
  expect_identical(attr(locs, "period"), "202512")
  expect_s3_class(attr(locs, "retrieved_at"), "POSIXct")
})

# B3 ------------------------------------------------------------------------
test_that("a national reference never removes a non-zero value", {
  x <- tibble::tibble(locality_id = "261160", period = "202401",
                      field = "bpc_ben_i", value = 90000)
  calls <- 0L
  local_mocked_bindings(mds_periods = function(field, ..., refresh = FALSE) {
    calls <<- calls + 1L
    tibble::tibble(period = "202401", n_localities = 1L, n_nonzero = 0L)
  })
  expect_warning(
    out <- mds_drop_unpublished(x, today = as.Date("2025-01-01"),
                                reference = "brazil"),
    class = "misocialr_warning_contradiction"
  )
  expect_identical(out$value, 90000)
  # The contradiction triggers one refreshed request.
  expect_identical(calls, 2L)
})

test_that("a refreshed reference that agrees with the data is used", {
  x <- tibble::tibble(locality_id = "261160", field = "bpc_ben_i",
                      period = c("202401", "202402"), value = c(5, 0))
  local_mocked_bindings(mds_periods = function(field, ..., refresh = FALSE) {
    last <- if (refresh) "202402" else "202312"
    tibble::tibble(period = last, n_localities = 1L, n_nonzero = 1L)
  })
  out <- suppressMessages(mds_drop_unpublished(
    x, today = as.Date("2025-01-01"), reference = "brazil"
  ))
  expect_identical(out$period, c("202401", "202402"))
})

# B4 ------------------------------------------------------------------------
test_that("conflicting values for the same key are an error", {
  out <- tibble::tibble(locality_id = "261160", period = "202401",
                        field = "a_i", value = c(10, 20))
  expect_error(dedupe_observations(out), class = "misocialr_error_conflict")
  same <- tibble::tibble(locality_id = "261160", period = "202401",
                         field = "a_i", value = c(10, 10))
  expect_identical(nrow(dedupe_observations(same)), 1L)
})

test_that("documents without municipality or month are an error", {
  docs <- list(list(municipio = "RECIFE", anomes_s = "202401", a_i = 1),
               list(municipio = "OLINDA", anomes_s = "202401", a_i = 2))
  expect_error(parse_docs(docs, "a_i"), "codigo_ibge")
  bad_month <- list(list(codigo_ibge = "261160", anomes_s = "2024", a_i = 1))
  expect_error(parse_docs(bad_month, "a_i"), "anomes_s")
})

test_that("a municipality inside a requested state is not requested twice", {
  plan <- build_query_plan("a_i", "202401",
                           list(states = "PE", municipalities = c("261160",
                                                                  "355030")))
  expect_length(plan, 2)
  expect_identical(plan[[2]]$fq[2], "codigo_ibge:(355030)")
  expect_match(plan[[1]]$fl, "^id,")
})

# B5 ------------------------------------------------------------------------
test_that("a list or several values in one document is an error", {
  docs <- list(
    list(codigo_ibge = "261160", anomes_s = "202401", a_i = list()),
    list(codigo_ibge = "260960", anomes_s = "202401", a_i = list(10, 20))
  )
  expect_error(parse_docs(docs, "a_i"), "single value")
  vec <- list(list(codigo_ibge = "261160", anomes_s = "202401", a_i = 1:2))
  expect_error(parse_docs(vec, "a_i"), "single value")
})

# B6 ------------------------------------------------------------------------
test_that("periods in the cleaning step must be real months", {
  for (p in c("202400", "202413")) {
    x <- tibble::tibble(period = p, field = "a_i", value = 1)
    expect_error(mds_drop_unpublished(x), "01 to 12")
  }
})

test_that("a factor period is read by its labels, not its codes", {
  x <- tibble::tibble(period = factor(c("202401", "202601")),
                      field = "a_i", value = 1)
  out <- suppressMessages(mds_drop_unpublished(x,
                                               today = as.Date("2025-01-01")))
  expect_identical(as.character(out$period), "202401")
  num <- tibble::tibble(period = c(202401, 202601), field = "a_i", value = 1)
  out <- suppressMessages(mds_drop_unpublished(num,
                                               today = as.Date("2025-01-01")))
  expect_identical(out$period, 202401)
})

# B7 ------------------------------------------------------------------------
test_that("field, today and value are validated", {
  x <- tibble::tibble(period = "202401", field = NA_character_, value = 1)
  expect_error(mds_drop_unpublished(x), "field")
  y <- tibble::tibble(period = "202401", field = "a_i", value = 1)
  expect_error(mds_drop_unpublished(y, today = NA), "single date")
  expect_error(mds_drop_unpublished(y, today = Sys.Date() + 0:1),
               "single date")
  z <- tibble::tibble(period = "202401", field = "a_i", value = Inf)
  expect_error(mds_drop_unpublished(z), "infinite")
})

test_that("a missing value is kept and flagged, never treated as zero", {
  x <- tibble::tibble(period = c("202401", "202402"), field = "a_i",
                      value = c(5, NA))
  out <- suppressMessages(mds_drop_unpublished(x,
                                               today = as.Date("2025-01-01")))
  expect_identical(out$period, c("202401", "202402"))
  f <- mds_drop_unpublished(x, today = as.Date("2025-01-01"), action = "flag")
  expect_identical(f$publication_status, c("published", "missing"))
})

# M2 ------------------------------------------------------------------------
test_that("action = 'flag' classifies every row without removing any", {
  x <- tibble::tibble(period = c("202506", "202507", "202508", "202601"),
                      field = "bpc_ben_i", value = c(10, 12, 0, 0))
  f <- mds_drop_unpublished(x, today = as.Date("2025-12-01"),
                            action = "flag")
  expect_identical(nrow(f), 4L)
  expect_identical(f$publication_status,
                   c("published", "published", "unpublished", "future"))
  expect_match(f$publication_reason[3], "202507")
  expect_identical(unique(f$publication_reference), "selection")
})

# B8 ------------------------------------------------------------------------
test_that("check_response enforces the response contract", {
  expect_error(check_response(list(response = list(numFound = 0L))), "docs")
  expect_error(check_response(list(response = list(numFound = -1L,
                                                   docs = list()))),
               "numFound")
  expect_error(check_response(list(response = list(numFound = 1.5,
                                                   docs = list()))),
               "numFound")
  expect_error(check_response(list(response = list(numFound = 1L,
                                                   docs = list(1)))),
               "list of documents")
  expect_error(check_response("x"), "response")
  expect_error(check_response(list(responseHeader = list(status = 500L),
                                   response = list(numFound = 0L,
                                                   docs = list()))),
               "status")
  expect_true(check_response(list(response = list(numFound = 0L)),
                             kind = "count"))
  expect_error(check_response(list(response = list(numFound = 0L)),
                              kind = "facet"), "facet_counts")
  expect_true(check_response(facet("202401", 3L), kind = "facet"))
})

# M1 ------------------------------------------------------------------------
test_that("refresh asks again and equivalent selections share the cache", {
  clear()
  calls <- 0L
  local_mocked_bindings(mds_request = function(...) {
    calls <<- calls + 1L
    facet("202401", 3L)
  })
  mds_periods("bpc_ben_i", localities = c("PE", "PB"))
  mds_periods("bpc_ben_i", localities = c("PB", "PE"))
  expect_identical(calls, 2L)
  mds_periods("bpc_ben_i", localities = c("PB", "PE"), refresh = TRUE)
  expect_identical(calls, 4L)
})

# M4 ------------------------------------------------------------------------
test_that("large selections are counted in disjoint blocks and summed", {
  clear()
  codes <- sprintf("26%04d", 1:450)
  seen <- character()
  local_mocked_bindings(
    validate_fields = function(...) invisible(TRUE),
    check_dv = function(...) invisible(TRUE),
    mds_request = function(query, ...) {
      seen <<- c(seen, query$fq[2])
      facet("202401", 2L)
    }
  )
  p <- mds_periods("bpc_ben_i", localities = codes)
  # 3 blocks of at most 200 codes, two facet queries each.
  expect_length(seen, 6)
  n_codes <- lengths(regmatches(seen, gregexpr("[0-9]{6}", seen)))
  expect_true(all(n_codes <= 200))
  expect_identical(sum(n_codes), 900L)
  expect_identical(p$n_localities, 6L)
})

# M5 ------------------------------------------------------------------------
test_that("a total that changes while paging is an error", {
  local_mocked_bindings(mds_page_size = 2L)
  local_mocked_bindings(mds_request = cursor_server(
    list(list(list(id = "a"), list(id = "b")), list(list(id = "c"))),
    totals = c(3L, 4L)
  ))
  expect_error(fetch_all_pages(list()), "changed while it was being read")
})

test_that("a document read twice is an error", {
  local_mocked_bindings(mds_request = cursor_server(
    list(list(list(id = "a")), list(list(id = "a")))
  ))
  expect_error(fetch_all_pages(list()), "same document twice")
})

test_that("a cursor that stops before numFound is an error", {
  local_mocked_bindings(mds_request = function(query, ...) {
    list(response = list(numFound = 3L, docs = list(list(id = "a"))),
         nextCursorMark = query$cursorMark)
  })
  expect_error(fetch_all_pages(list()), "Incomplete response",
               class = "misocialr_error_response")
})

test_that("cursorMark is sent with a sort on the unique key", {
  seen <- NULL
  local_mocked_bindings(mds_request = function(query, ...) {
    seen <<- query
    list(response = list(numFound = 0L, docs = list()))
  })
  fetch_all_pages(list(fq = "x"))
  expect_identical(seen$cursorMark, "*")
  expect_identical(seen$sort, "id asc")
  expect_null(seen$start)
})

# M6 ------------------------------------------------------------------------
test_that("ibge_code7 gives the same result for repeated codes", {
  x <- rep(c("261160", "261153", NA, "12345"), 1000)
  expect_identical(ibge_code7(x),
                   rep(c("2611606", "2611533", NA, NA), 1000))
})

# M7 ------------------------------------------------------------------------
test_that("local checks run even with validate = FALSE", {
  expect_error(mds_data(1, validate = FALSE), "character vector")
  expect_error(mds_data("a b", validate = FALSE), "Invalid field name")
  expect_error(mds_data("bpc_ben_i", validate = NA), "TRUE")
  expect_error(mds_data("id", validate = FALSE), "not a")
})

# M8 ------------------------------------------------------------------------
test_that("HTTP errors are classed and keep the original error", {
  withr::local_options(misocialr.quiet = TRUE)
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 400,
      body = charToRaw('{"error":{"msg":"undefined field x_i","code":400}}')
    )
  })
  err <- tryCatch(mds_request(list(rows = 0)), error = function(e) e)
  expect_s3_class(err, "misocialr_error_http")
  expect_s3_class(err, "misocialr_error")
  expect_identical(err$status, 400L)
  expect_s3_class(err$parent, "httr2_http_400")
  # field_exists() reads "undefined field" from the classed error.
  expect_false(field_exists("x_i"))
})

test_that("the user agent carries the package version", {
  expect_match(user_agent(), paste0("^misocialr/",
                                    utils::packageVersion("misocialr")))
})

test_that("mds_request retries on connection failure", {
  body <- deparse(mds_request)
  expect_true(any(grepl("retry_on_failure = TRUE", body, fixed = TRUE)))
})

# M9 ------------------------------------------------------------------------
test_that("a requested municipality without documents raises a warning", {
  local_mocked_bindings(fetch_all_pages = function(...) list())
  expect_warning(
    mds_data("bpc_ben_i", periods = 202401, localities = 1100015),
    class = "misocialr_warning_missing"
  )
})

# M3 ------------------------------------------------------------------------
test_that("storage type and unit are kept apart", {
  expect_identical(unit_from_suffix(c("a_s", "a_i", "regiao")),
                   c("unknown", "count", "unknown"))
  expect_identical(storage_from_suffix(c("a_s", "a_i", "a_l", "x")),
                   c("string", "integer", "long", "untyped"))
  expect_true("storage_type" %in% names(mds_fields()))
})
