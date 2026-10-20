# One-off: append the four themes added in 0.2.0 to inst/extdata.
# Kept for the record of how the dictionary was built.
d <- utils::read.csv("inst/extdata/dictionary.csv", encoding = "UTF-8", colClasses = "character")
n <- utils::read.csv("data-raw/new_themes_rows.csv", sep = "|", encoding = "UTF-8", colClasses = "character")
stopifnot(!any(paste(n$theme, n$field) %in% paste(d$theme, d$field)))
utils::write.csv(rbind(d, n), "inst/extdata/dictionary.csv", row.names = FALSE, fileEncoding = "UTF-8")

t <- utils::read.csv("inst/extdata/themes.csv", encoding = "UTF-8", colClasses = "character")
t <- rbind(t, data.frame(
  theme = c("suas_rede", "suas_financiamento", "pbf_condicionalidades", "seguranca_alimentar"),
  name = c("Rede socioassistencial (CadSUAS)", "Financiamento do SUAS",
           "Condicionalidades do Bolsa Família", "Segurança alimentar e nutricional"),
  description = c(
    "Unidades CRAS, CREAS, Centro POP, centros de convivência e centros-dia, acolhimento, e profissionais por tipo de unidade",
    "Repasses e saldos do FNAS aos fundos municipais e IGD-M",
    "Acompanhamento de educação e saúde (SICON) e repercussões por descumprimento",
    "PAA, Fomento Rural e cisternas"
  )
))
utils::write.csv(t, "inst/extdata/themes.csv", row.names = FALSE, fileEncoding = "UTF-8")
