# Cases from the final report on 0.3.0
# (fixes in NEWS.md, 0.3.1). Parity cases are in test-paridade.R.

clear <- function(env = parent.frame()) {
  suppressMessages(mds_clear_cache())
  withr::defer(suppressMessages(mds_clear_cache()), envir = env)
}
facet <- function(...) {
  list(response = list(numFound = 0L, docs = list()),
       facet_counts = list(facet_fields = list(anomes_s = list(...))))
}

test_that("F2: action = 'flag' keeps its columns on an empty table", {
  f <- mds_drop_unpublished(empty_result(), action = "flag")
  expect_identical(nrow(f), 0L)
  expect_true(all(c("publication_status", "publication_reason",
                    "publication_reference") %in% names(f)))
  expect_type(f$publication_status, "character")
})

test_that("F5: disagreeing facets are read again, then an error", {
  clear()
  calls <- 0L
  local_mocked_bindings(mds_request = function(query, ...) {
    calls <<- calls + 1L
    if (grepl("-bpc_ben_i", query$fq[1], fixed = TRUE)) facet("202401", 2L)
    else facet("202401", 1L)
  })
  expect_error(mds_periods("bpc_ben_i"), "disagree",
               class = "misocialr_error_response")
  expect_identical(calls, 4L)
  expect_length(ls(.misocialr_cache), 0)
})

test_that("F5: facets that agree on the second read are used", {
  clear()
  calls <- 0L
  local_mocked_bindings(mds_request = function(query, ...) {
    calls <<- calls + 1L
    nonzero <- grepl("-bpc_ben_i", query$fq[1], fixed = TRUE)
    if (nonzero && calls <= 2L) facet("202401", 5L) else facet("202401", 3L)
  })
  p <- mds_periods("bpc_ben_i")
  expect_identical(p$n_nonzero, 3L)
  expect_identical(calls, 4L)
})

test_that("F5: documents beyond numFound are an error", {
  local_mocked_bindings(mds_request = function(...) {
    list(response = list(numFound = 0L, docs = list(list(id = "a"))))
  })
  expect_error(fetch_all_pages(list()), "numFound",
               class = "misocialr_error_response")
})

test_that("F6: a body that is not JSON is a classed response error", {
  withr::local_options(misocialr.quiet = TRUE)
  httr2::local_mocked_responses(function(req) {
    httr2::response(status_code = 200, body = charToRaw("<html>"))
  })
  err <- tryCatch(mds_request(list(rows = 0)), error = function(e) e)
  expect_s3_class(err, "misocialr_error_response")
  expect_match(conditionMessage(err), "not valid JSON")
  expect_false(is.null(err$parent))
})

# Retries are tested against a real local HTTP server: httr2's mocked
# responses return before the retry loop and would not exercise it.
fake_api <- function(fail, status = 503L) {
  app <- webfakes::new_app()
  app$locals$n <- 0L
  app$locals$fail <- fail
  app$locals$status <- status
  app$get("/count", function(req, res) res$send(as.character(app$locals$n)))
  app$post("/", function(req, res) {
    app$locals$n <- app$locals$n + 1L
    if (app$locals$n <= app$locals$fail) {
      res$set_status(app$locals$status)$send("busy")
    } else {
      res$set_type("text/plain")$send('{"response":{"numFound":0,"docs":[]}}')
    }
  })
  webfakes::local_app_process(app, .local_envir = parent.frame())
}
requests_made <- function(srv) {
  as.integer(readLines(paste0(srv$url(), "count"), warn = FALSE))
}

test_that("a transient 503 is retried and the next answer is used", {
  skip_if_not_installed("webfakes")
  withr::local_options(misocialr.quiet = TRUE, misocialr.retry_backoff = 0)
  srv <- fake_api(fail = 1L)
  local_mocked_bindings(mds_base_url = srv$url())
  expect_identical(mds_request(list(rows = 0))$response$numFound, 0L)
  expect_identical(requests_made(srv), 2L)
})

test_that("retries stop after three tries with a classed HTTP error", {
  skip_if_not_installed("webfakes")
  withr::local_options(misocialr.quiet = TRUE, misocialr.retry_backoff = 0)
  srv <- fake_api(fail = 10L)
  local_mocked_bindings(mds_base_url = srv$url())
  err <- tryCatch(mds_request(list(rows = 0)), error = function(e) e)
  expect_s3_class(err, "misocialr_error_http")
  expect_identical(err$status, 503L)
  expect_identical(requests_made(srv), 3L)
})

test_that("a 400 is not retried", {
  skip_if_not_installed("webfakes")
  withr::local_options(misocialr.quiet = TRUE, misocialr.retry_backoff = 0)
  srv <- fake_api(fail = 10L, status = 400L)
  local_mocked_bindings(mds_base_url = srv$url())
  err <- tryCatch(mds_request(list(rows = 0)), error = function(e) e)
  expect_s3_class(err, "misocialr_error_http")
  expect_identical(err$status, 400L)
  expect_identical(requests_made(srv), 1L)
})

test_that("misocialr.cache_ttl makes old cached results expire", {
  suppressMessages(mds_clear_cache())
  withr::defer(suppressMessages(mds_clear_cache()))
  calls <- 0L
  local_mocked_bindings(mds_request = function(...) {
    calls <<- calls + 1L
    facet("202401", 3L)
  })
  mds_periods("bpc_ben_i")
  mds_periods("bpc_ben_i")
  expect_identical(calls, 2L)
  withr::local_options(misocialr.cache_ttl = 0)
  Sys.sleep(0.01)
  mds_periods("bpc_ben_i")
  expect_identical(calls, 4L)
  withr::local_options(misocialr.cache_ttl = -1)
  expect_error(mds_periods("bpc_ben_i"), "cache_ttl",
               class = "misocialr_error_validation")
})

test_that("every field has a nature and the basis of that classification", {
  d <- mds_fields()
  expect_true(all(d$nature %in% c("estoque", "fluxo", "fluxo anual",
                                  "acumulado", "taxa", "média", "índice")))
  expect_true(all(d$nature_basis %in% c("medido",
                                        "mesmo grupo de um campo medido",
                                        "rótulo e unidade")))
  expect_true(all(d$nature[d$unit %in% c("%", "Proporção")] == "taxa"))
  expect_true(all(grepl("acumulado", d$label[d$nature == "acumulado"])))
  # The "_ano" Fomento field equals the monthly one (14,755 of 14,755
  # municipality-months, Brazil 2013-2026): it is not a yearly total.
  campo <- "fomento_vl_recuros_disponibilizados_as_familias_ano_f"
  ano <- d$label[d$field == campo]
  expect_false(grepl("no ano", ano))
})
