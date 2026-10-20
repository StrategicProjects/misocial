test_that("ibge_code7 applies the check-digit rule", {
  expect_identical(ibge_code7(c(261160, "260790", "530010")),
                   c("2611606", "2607901", "5300108"))
})

test_that("ibge_code7 uses the exception table", {
  # Codes that do not follow the check-digit rule (verified against the
  # IBGE localities API).
  expect_identical(ibge_code7(c("261153", "220191", "520396")),
                   c("2611533", "2201919", "5203962"))
  expect_length(ibge_dv_exceptions, 9)
})

test_that("ibge_code7 returns NA for malformed input", {
  expect_identical(ibge_code7(c("26116", "2611606", NA)),
                   rep(NA_character_, 3))
})

test_that("normalize_municipality accepts 6 or 7 digits", {
  expect_identical(normalize_municipality(2611606), "261160")
  expect_identical(normalize_municipality("261160"), "261160")
  expect_error(normalize_municipality("PE"), "6- or 7-digit")
  expect_error(normalize_municipality(c(1, 2)), "single")
})

test_that("states_to_abbr maps codes and abbreviations", {
  expect_identical(states_to_abbr(c("pe", 26, "35")), c("PE", "PE", "SP"))
  expect_error(states_to_abbr("XX"), "Unknown state")
})

test_that("parse_localities handles every accepted form", {
  br <- parse_localities("BR")
  expect_length(br$states, 0)
  expect_length(br$municipalities, 0)

  mixed <- parse_localities(c("PE", 25, 2611606, "260790", "2611606"))
  expect_identical(mixed$states, c("PE", "PB"))
  expect_identical(mixed$municipalities, c("261160", "260790"))

  expect_error(parse_localities("Recife"), "Invalid locality")
  expect_error(parse_localities(NULL), "at least one value")
})

test_that("localities_period is December of the previous year", {
  expect_identical(localities_period(as.Date("2026-10-19")), "202512")
})
