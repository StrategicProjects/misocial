test_that("parse_periods expands years and keeps months", {
  expect_identical(parse_periods(2024),
                   paste0("2024", sprintf("%02d", 1:12)))
  expect_identical(parse_periods(c("202402", 202401)), c("202401", "202402"))
  expect_length(parse_periods(c(2023, 2024, 202501)), 25)
})

test_that("parse_periods rejects invalid months", {
  expect_error(parse_periods(202413), "Invalid period")
  expect_error(parse_periods("2024-01"), "Invalid period")
})

test_that("negative periods count back from the current month", {
  expect_identical(last_months(3, today = as.Date("2026-02-15")),
                   c("202512", "202601", "202602"))
  expect_length(parse_periods(-6), 6)
  expect_length(parse_periods(NULL), 12)
})
