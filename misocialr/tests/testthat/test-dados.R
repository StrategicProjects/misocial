test_that("the dictionary is consistent", {
  expect_false(anyDuplicated(mds_dictionary[, c("theme", "field")]) > 0)
  # A field repeated across themes keeps the same label and unit.
  per_field <- dplyr::distinct(mds_dictionary, .data$field, .data$label,
                               .data$unit)
  expect_false(anyDuplicated(per_field$field) > 0)
  expect_setequal(unique(mds_dictionary$theme), mds_theme_table$theme)
  expect_true(all(grepl("_[ifdl]$", mds_dictionary$field)))
  expect_false(anyNA(mds_dictionary$label))
})

test_that("mds_fields filters by theme and validates it", {
  expect_true(all(mds_fields("bpc_suas")$theme == "bpc_suas"))
  expect_true("cadsuas_qtd_cras_i" %in% mds_fields("bpc_suas")$field)
  expect_identical(nrow(mds_fields()), nrow(mds_dictionary))
  expect_error(mds_fields("saude"), "Unknown theme")
})

test_that("mds_themes counts fields per theme", {
  th <- mds_themes()
  expect_identical(sum(th$n_fields), nrow(mds_dictionary))
})

test_that("build_query_plan splits long municipality lists", {
  codes <- sprintf("26%04d", 1:450)
  plan <- build_query_plan(
    "bpc_ben_i", c("202401", "202402"),
    list(states = "PB", municipalities = codes)
  )
  expect_length(plan, 4)
  expect_identical(plan[[1]]$fq[1], "anomes_s:(202401 OR 202402)")
  expect_identical(plan[[1]]$fq[2], "sigla_uf:(PB)")
  expect_match(plan[[2]]$fq[2], "^codigo_ibge:\\(260001 OR")
  expect_match(plan[[1]]$fl,
               "codigo_ibge,municipio,sigla_uf,anomes_s,bpc_ben_i")
})

test_that("build_query_plan without localities has a single request", {
  no_loc <- list(states = character(), municipalities = character())
  plan <- build_query_plan("bpc_ben_i", "202401", no_loc)
  expect_length(plan, 1)
  expect_identical(plan[[1]]$fq, "anomes_s:(202401)")
})

test_that("parse_docs flattens sparse documents", {
  docs <- list(
    list(codigo_ibge = "261160", municipio = "RECIFE", sigla_uf = "PE",
         anomes_s = "202402", bpc_ben_i = 90187L, cadsuas_qtd_cras_i = 16L),
    list(codigo_ibge = "261160", municipio = "RECIFE", sigla_uf = "PE",
         anomes_s = "202401", bpc_ben_i = 90000L),
    list(codigo_ibge = "261160", municipio = "RECIFE", sigla_uf = "PE",
         anomes_s = "202401", outro_campo_i = 1L)
  )
  out <- parse_docs(docs, c("bpc_ben_i", "cadsuas_qtd_cras_i", "outro_campo_i"))

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("locality_id", "ibge_code", "locality_name", "state",
                      "period", "field", "label", "unit", "value"))
  expect_identical(nrow(out), 4L)
  expect_identical(out$field, c("bpc_ben_i", "bpc_ben_i",
                                "cadsuas_qtd_cras_i", "outro_campo_i"))
  expect_identical(out$period[1:2], c("202401", "202402"))
  expect_identical(unique(out$ibge_code), "2611606")
  expect_type(out$value, "double")
  # Fields outside the dictionary fall back to the technical name and suffix.
  expect_identical(out$label[4], "outro_campo_i")
  expect_identical(out$unit[4], "count")
  expect_identical(out$label[1], "Beneficiários do BPC")
})

test_that("parse_docs returns a typed empty tibble", {
  out <- parse_docs(list(), "bpc_ben_i")
  expect_identical(nrow(out), 0L)
  expect_type(out$value, "double")
})

test_that("every theme shortcut requests the curated fields of its theme", {
  shortcuts <- list(
    cadunico = mds_cadunico, bolsa_familia = mds_bolsa_familia,
    bpc_suas = mds_bpc_suas, suas_rede = mds_suas_rede,
    suas_financiamento = mds_suas_financiamento,
    pbf_condicionalidades = mds_pbf_condicionalidades,
    seguranca_alimentar = mds_seguranca_alimentar
  )
  expect_setequal(names(shortcuts), mds_theme_table$theme)
  local_mocked_bindings(mds_data = function(fields, ...) fields)
  for (th in names(shortcuts)) {
    expect_identical(shortcuts[[th]](periods = 202401), mds_fields(th)$field)
  }
})

test_that("a field in two themes produces a single row per value", {
  docs <- list(list(codigo_ibge = "261160", municipio = "RECIFE",
                    sigla_uf = "PE", anomes_s = "202609",
                    cadsuas_qtd_cras_i = 18L))
  out <- parse_docs(docs, "cadsuas_qtd_cras_i")
  expect_identical(nrow(out), 1L)
  expect_identical(out$label, "Unidades CRAS")
})
