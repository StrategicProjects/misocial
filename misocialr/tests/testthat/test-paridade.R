# Behaviour shared with the Python package: the same cases
# (paridade/casos.json) run in both test suites. Inputs use JSON null for
# NA; errors are named by class (validation, response, conflict).

casos <- jsonlite::fromJSON(test_path("paridade", "casos.json"),
                            simplifyVector = FALSE)

vec <- function(x) {
  if (length(x) == 0) return(character())
  x <- lapply(x, function(v) if (is.null(v)) NA else v)
  if (any(vapply(x, is.character, logical(1)))) {
    return(vapply(x, function(v) {
      if (is.na(v)) NA_character_ else as.character(v)
    }, character(1)))
  }
  as.numeric(unlist(x))
}
err_class <- function(kind) paste0("misocialr_error_", kind)

test_that("parse_periods behaves as in Python", {
  for (cs in casos$parse_periods) {
    input <- vec(cs$input)
    if (!is.null(cs$error)) {
      expect_error(parse_periods(input), class = err_class(cs$error),
                   info = deparse(input))
    } else if (!is.null(cs$length)) {
      expect_length(parse_periods(input), cs$length)
    } else {
      expect_identical(parse_periods(input), vec(cs$output))
    }
  }
})

test_that("parse_localities behaves as in Python", {
  for (cs in casos$parse_localities) {
    input <- vec(cs$input)
    if (!is.null(cs$error)) {
      expect_error(parse_localities(input), class = err_class(cs$error),
                   info = deparse(input))
    } else {
      out <- parse_localities(input)
      expect_identical(out$states, vec(cs$states), info = deparse(input))
      expect_identical(out$municipalities, vec(cs$municipalities),
                       info = deparse(input))
    }
  }
})

test_that("ibge_code7 behaves as in Python", {
  for (cs in casos$ibge_code7) {
    expect_identical(ibge_code7(vec(cs$input)), vec(cs$output))
  }
})

test_that("values per document behave as in Python", {
  for (cs in casos$doc_value) {
    docs <- list(list(a_i = cs$value))
    if (!is.null(cs$error)) {
      expect_error(doc_values(docs, "a_i"), class = err_class(cs$error),
                   info = deparse(cs$value))
    } else {
      expect_identical(doc_values(docs, "a_i")$value, as.numeric(cs$output))
    }
  }
})

test_that("de-duplication behaves as in Python", {
  for (cs in casos$dedupe) {
    out <- tibble::tibble(locality_id = "261160", period = "202401",
                          field = "a_i", value = vec(cs$values))
    if (!is.null(cs$error)) {
      expect_error(dedupe_observations(out), class = err_class(cs$error))
    } else {
      expect_identical(dedupe_observations(out)$value, vec(cs$output))
    }
  }
})

test_that("the response contract behaves as in Python", {
  for (cs in casos$check_response) {
    if (isTRUE(cs$ok)) {
      expect_true(check_response(cs$res, kind = cs$kind))
    } else {
      expect_error(check_response(cs$res, kind = cs$kind),
                   class = err_class(cs$error), info = cs$kind)
    }
  }
})

test_that("mds_drop_unpublished classifies as in Python", {
  for (cs in casos$drop_unpublished) {
    x <- tibble::tibble(period = vec(cs$period), field = vec(cs$field),
                        value = vec(cs$value))
    if (all(is.na(x$field))) x$field <- NA_character_
    run <- function() {
      mds_drop_unpublished(x, today = as.Date(cs$today),
                           reference = cs$reference, action = "flag")
    }
    if (!is.null(cs$error)) {
      expect_error(run(), class = err_class(cs$error))
    } else {
      expect_identical(run()$publication_status, vec(cs$status))
    }
  }
})
