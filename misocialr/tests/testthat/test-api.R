# Integration tests against recorded API responses (httptest2).
#
# On the first run with network access, `with_mock_dir()` records real
# responses under `tests/testthat/api/`; subsequent runs replay them
# offline, so these tests never hit the network on CI/CRAN.

skip_if_not_installed("httptest2")

# Each test clears the session cache first so requests always go through
# the (mocked) HTTP layer instead of the in-memory cache.
local_clear_cache <- function(env = parent.frame()) {
  suppressMessages(mds_clear_cache())
  withr::defer(suppressMessages(mds_clear_cache()), envir = env)
}

test_that("mds_data fetches and tidies a small query", {
  local_clear_cache()
  httptest2::with_mock_dir("api", {
    out <- mds_data(
      c("qtd_familias_beneficiarias_bolsa_familia_i", "bpc_ben_i"),
      periods = c(202402, 202509),
      localities = c(2611606, 2607901)
    )
  })

  expect_s3_class(out, "tbl_df")
  expect_identical(nrow(out), 8L)
  expect_setequal(out$ibge_code, c("2611606", "2607901"))
  recife <- out[
    out$locality_id == "261160" & out$period == "202402" &
      out$field == "qtd_familias_beneficiarias_bolsa_familia_i",
  ]
  expect_identical(recife$value, 146737)
  expect_identical(recife$unit, "Famílias")
})

test_that("theme shortcuts request their curated fields", {
  local_clear_cache()
  httptest2::with_mock_dir("api", {
    out <- mds_bpc_suas(periods = 202509, localities = 2611606)
  })
  expect_setequal(unique(out$field), mds_fields("bpc_suas")$field)
  expect_identical(out$value[out$field == "cadsuas_qtd_cras_i"], 16)
})

test_that("mds_periods separates published values from zeros", {
  local_clear_cache()
  httptest2::with_mock_dir("api", {
    p <- mds_periods("bpc_ben_i", localities = "PE")
  })
  expect_named(p, c("period", "n_localities", "n_nonzero"))
  expect_identical(p$period[1], "200301")
  expect_true(all(p$n_localities == 185L))
  # The recording has months already listed but still all zero.
  expect_true(any(p$n_nonzero == 0L))

  # Second call comes from the cache (no HTTP)
  expect_identical(mds_periods("bpc_ben_i", localities = "PE"), p)
})

test_that("mds_localities lists municipalities with 7-digit codes", {
  local_clear_cache()
  local_mocked_bindings(localities_period = function(...) "202512")
  httptest2::with_mock_dir("api", {
    locs <- mds_localities()
  })
  expect_identical(nrow(locs), 5571L)
  expect_false(anyNA(locs$ibge_code))
  expect_identical(nrow(mds_localities("PE")), 185L)
  expect_identical(locs$locality_name[locs$ibge_code == "2611606"], "RECIFE")
})

test_that("unknown fields are rejected before any data request", {
  local_clear_cache()
  httptest2::with_mock_dir("api", {
    expect_error(
      suppressMessages(mds_data("campo_inexistente_i", periods = 202401,
                                localities = "PE")),
      "not found"
    )
  })
})
