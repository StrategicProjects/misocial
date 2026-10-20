# Cases from the external review of 0.2.0 (docs in NEWS.md, 0.2.1).

test_that("an empty or missing locality is an error, not the whole country", {
  expect_error(parse_localities(character(0)), "at least one value")
  expect_error(parse_localities(NULL), "at least one value")
  expect_error(parse_localities(NA), "at least one value")
  expect_error(parse_localities(c("PE", "")), "at least one value")
})

test_that("every locality is validated, even next to BR", {
  expect_error(parse_localities(c("BR", "Recifex")), "Invalid locality")
  expect_error(parse_localities(c("BR", "99")), "Unknown state")
  br <- parse_localities(c("BR", "PE", 2611606))
  expect_length(br$states, 0)
  expect_length(br$municipalities, 0)
})

test_that("a 7-digit code with a wrong check digit is rejected", {
  expect_error(parse_localities(2611600), "Wrong check digit")
  expect_error(parse_localities(2611600), "2611606")
  expect_error(normalize_municipality(2611600), "Wrong check digit")
  # Exceptions to the check-digit rule are accepted.
  expect_identical(parse_localities(2611533)$municipalities, "261153")
  expect_identical(parse_localities(261160)$municipalities, "261160")
})

test_that("periods must be whole, finite, non-missing and non-empty", {
  expect_error(parse_periods(-1.9), "whole numbers")
  expect_error(parse_periods(202401.5), "whole numbers")
  expect_error(parse_periods(Inf), "whole numbers")
  expect_error(parse_periods(NA_real_), "no missing values")
  expect_error(parse_periods(c(202401, NA)), "no missing values")
  expect_error(parse_periods(character(0)), "at least one value")
  expect_error(parse_periods(c(-3, 202401)), "used alone")
  expect_error(parse_periods(0), "Invalid period")
  expect_identical(parse_periods(c(2024, 202501))[13], "202501")
})

test_that("a text field is an error instead of an empty result", {
  docs <- list(list(codigo_ibge = "261160", municipio = "RECIFE",
                    sigla_uf = "PE", anomes_s = "202401",
                    regiao = "NORDESTE"))
  expect_error(parse_docs(docs, "regiao"), "not numeric")
  expect_error(parse_docs(docs, "regiao"), "NORDESTE")
})

test_that("numbers sent as strings are still read", {
  docs <- list(list(codigo_ibge = "261160", anomes_s = "202402",
                    valor_repassado_bolsa_familia_s = "98463694.0"))
  out <- parse_docs(docs, "valor_repassado_bolsa_familia_s")
  expect_identical(out$value, 98463694)
})

test_that("identification fields cannot be requested as measures", {
  expect_error(validate_fields(c("bpc_ben_i", "municipio")), "not a")
})

test_that("pagination reads every page and fails on an empty page", {
  local_mocked_bindings(mds_page_size = 2L)
  d <- function(i) list(id = as.character(i))
  seen <- character()
  local_mocked_bindings(mds_request = cursor_server(
    list(list(d(1), d(2)), list(d(3), d(4)), list(d(5))),
    on_call = function(query) seen <<- c(seen, query$cursorMark)
  ))
  expect_identical(unname(unlist(fetch_all_pages(list()))),
                   as.character(1:5))
  # Three pages, read by cursor; no extra request once numFound is reached.
  expect_identical(seen, c("*", "2", "3"))

  local_mocked_bindings(mds_request = function(...) {
    list(response = list(numFound = 3L, docs = list()))
  })
  expect_error(fetch_all_pages(list()), "Incomplete response")
})

test_that("partial and malformed responses are errors", {
  local_mocked_bindings(mds_request = function(...) {
    list(responseHeader = list(partialResults = TRUE),
         response = list(numFound = 1L, docs = list(list(id = "a"))))
  })
  expect_error(fetch_all_pages(list()), "Partial results")

  local_mocked_bindings(mds_request = function(...) list(error = "x"))
  expect_error(fetch_all_pages(list()), "Unexpected response")
})

test_that("mds_api_fields returns a typed empty table for an empty locality", {
  local_clear <- function() suppressMessages(mds_clear_cache())
  local_clear()
  withr::defer(local_clear())
  local_mocked_bindings(mds_request = function(...) {
    list(response = list(numFound = 0L, docs = list()))
  })
  expect_warning(out <- mds_api_fields(999999), "no document")
  expect_identical(nrow(out), 0L)
  expect_named(out, c("field", "unit", "storage_type", "in_dictionary",
                      "first_period", "last_period"))
})

test_that("mds_api_fields pages through the whole history", {
  local_clear <- function() suppressMessages(mds_clear_cache())
  local_clear()
  withr::defer(local_clear())
  local_mocked_bindings(mds_page_size = 1L)
  docs <- list(list(anomes_s = "202401", bpc_ben_i = 1L),
               list(anomes_s = "202402", bpc_ben_i = 2L, outro_l = 3L))
  local_mocked_bindings(mds_request = cursor_server(list(docs[1], docs[2])))
  out <- mds_api_fields(261160)
  expect_identical(out$field, c("bpc_ben_i", "outro_l"))
  expect_identical(out$first_period, c("202401", "202402"))
  expect_identical(out$unit, c("count", "count"))
})

test_that("HTTP errors carry the Solr message and are not retried on 400", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    httr2::response(
      status_code = 400,
      headers = list(`Content-Type` = "text/plain"),
      body = charToRaw('{"error":{"msg":"undefined field xyz","code":400}}')
    )
  })
  expect_error(suppressMessages(mds_request(list(rows = 0))),
               "undefined field xyz")
  expect_identical(calls, 1L)
})

test_that("mds_drop_unpublished validates period and value", {
  x <- tibble::tibble(period = c("202401", NA), field = "a_i", value = 1:2)
  expect_error(mds_drop_unpublished(x), "YYYYMM")
  y <- tibble::tibble(period = "2024-01", field = "a_i", value = 1)
  expect_error(mds_drop_unpublished(y), "YYYYMM")
  z <- tibble::tibble(period = "202401", field = "a_i", value = "1")
  expect_error(mds_drop_unpublished(z), "numeric")
})

test_that("reference = 'brazil' keeps the legitimate zeros of a selection", {
  # One small municipality ends in zeros, but Brazil has values up to 202509.
  x <- tibble::tibble(
    locality_id = "260005", field = "cadsuas_qtd_creas_i",
    period = c("202507", "202508", "202509", "202510"),
    value = c(1, 0, 0, 0)
  )
  local_mocked_bindings(mds_periods = function(field, ...) {
    tibble::tibble(period = c("202508", "202509", "202510"),
                   n_localities = 5570L, n_nonzero = c(2000L, 2000L, 0L))
  })
  today <- as.Date("2025-12-01")
  sel <- suppressMessages(mds_drop_unpublished(x, today = today))
  expect_identical(sel$period, "202507")
  br <- suppressMessages(
    mds_drop_unpublished(x, today = today, reference = "brazil")
  )
  expect_identical(br$period, c("202507", "202508", "202509"))
  expect_message(mds_drop_unpublished(x, today = today, reference = "brazil"),
                 "published in Brazil")
})

test_that("mds_data records the time of the request", {
  local_mocked_bindings(
    validate_fields = function(...) invisible(TRUE),
    fetch_all_pages = function(...) {
      list(list(codigo_ibge = "261160", anomes_s = "202401", bpc_ben_i = 1L))
    }
  )
  out <- mds_data("bpc_ben_i", periods = 202401, localities = 2611606)
  expect_s3_class(attr(out, "retrieved_at"), "POSIXct")
})

test_that("the timeout can be set with an option", {
  withr::local_options(misocialr.timeout = 7)
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req$options$timeout_ms
    httr2::response(status_code = 200,
                    body = charToRaw('{"response":{"numFound":0,"docs":[]}}'))
  })
  suppressMessages(mds_request(list(rows = 0)))
  expect_identical(as.numeric(seen), 7000)
})
