# Check, against the live API, that every curated field has values and
# print the period range in which it is published.
#
#   Rscript data-raw/check_dictionary.R

pkgload::load_all(".", quiet = TRUE)

dict <- mds_fields()
res <- purrr::map(dict$field, function(f) {
  p <- suppressMessages(mds_periods(f))
  pub <- p[p$n_nonzero > 0, ]
  tibble::tibble(
    field = f,
    exists = nrow(p) > 0,
    first = if (nrow(pub)) min(pub$period) else NA_character_,
    last  = if (nrow(pub)) max(pub$period) else NA_character_
  )
}) |>
  purrr::list_rbind()

print(res, n = Inf)
cat("\nFields with values:", sum(res$exists), "of", nrow(res), "\n")
