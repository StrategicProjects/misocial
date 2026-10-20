test_that("solr_in builds an OR disjunction", {
  expect_identical(solr_in("anomes_s", c("202401", "202402")),
                   "anomes_s:(202401 OR 202402)")
  expect_identical(solr_in("sigla_uf", "PE"), "sigla_uf:(PE)")
})

test_that("solr_has builds an existence filter", {
  expect_identical(solr_has("bpc_ben_i"), "bpc_ben_i:[* TO *]")
})

test_that("chunk_vector splits in groups of at most size", {
  ch <- chunk_vector(1:450, 200)
  expect_length(ch, 3)
  expect_identical(lengths(ch, use.names = FALSE), c(200L, 200L, 50L))
  expect_identical(unlist(ch, use.names = FALSE), 1:450)
  expect_length(chunk_vector(character(), 200), 1)
})

test_that("unit_from_suffix reads the dynamic-field type", {
  expect_identical(
    unit_from_suffix(c("a_i", "a_l", "a_f", "a_d", "a_s", "municipio")),
    c("count", "count", "value", "rate", "unknown", "unknown")
  )
})

test_that("parse_facet turns a Solr facet list into a tibble", {
  f <- parse_facet(list("202401", 185L, "202402", 184L))
  expect_s3_class(f, "tbl_df")
  expect_identical(f$period, c("202401", "202402"))
  expect_identical(f$n, c(185L, 184L))
  expect_identical(nrow(parse_facet(list())), 0L)
})
