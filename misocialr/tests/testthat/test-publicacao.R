make_series <- function() {
  tibble::tibble(
    locality_id = rep(c("261160", "260790"), each = 6),
    period = rep(as.character(202505:202510), 2),
    field = "bpc_ben_i",
    value = c(10, 0, 12, 13, 0, 0,
              20, 0, 22, 23, 0, 0)
  )
}

drop_quiet <- function(x, today = as.Date("2025-12-01")) {
  suppressMessages(mds_drop_unpublished(x, today = today))
}

test_that("trailing all-zero months are dropped, middle zeros kept", {
  out <- suppressMessages(
    mds_drop_unpublished(make_series(), today = as.Date("2025-12-01"))
  )
  expect_identical(sort(unique(out$period)),
                   c("202505", "202506", "202507", "202508"))
  # 202506 is zero everywhere but followed by values: a real zero.
  expect_identical(sum(out$period == "202506"), 2L)
})

test_that("future months are dropped", {
  out <- suppressMessages(
    mds_drop_unpublished(make_series(), today = as.Date("2025-07-10"))
  )
  expect_identical(max(out$period), "202507")
})

test_that("a trailing zero in one locality only is kept", {
  x <- make_series()
  x$value[x$locality_id == "260790" & x$period == "202509"] <- 5
  out <- drop_quiet(x)
  expect_identical(max(out$period), "202509")
  expect_identical(sum(out$period == "202509"), 2L)
})

test_that("a field without any non-zero value is dropped entirely", {
  x <- make_series()
  x$value <- 0
  out <- drop_quiet(x)
  expect_identical(nrow(out), 0L)
})

test_that("fields are handled independently", {
  x <- dplyr::bind_rows(
    make_series(),
    dplyr::mutate(make_series(), field = "bpc_val_f", value = value + 1)
  )
  out <- drop_quiet(x)
  expect_identical(max(out$period[out$field == "bpc_val_f"]), "202510")
  expect_identical(max(out$period[out$field == "bpc_ben_i"]), "202508")
})

test_that("mds_drop_unpublished reports and validates input", {
  dec <- as.Date("2025-12-01")
  expect_message(mds_drop_unpublished(make_series(), today = dec),
                 "trailing all-zero")
  expect_error(mds_drop_unpublished(tibble::tibble(x = 1)), "must have columns")
})
