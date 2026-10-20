# Re-record the httptest2 fixtures used by tests/testthat/test-api.R.
#
# Run from the package root, with network access:
#   Rscript data-raw/record_fixtures.R
# Every request made inside capture_requests() is saved, keyed by a hash of
# the URL.
#
# The recording goes to a temporary folder first. Only when every call
# succeeded and the expected number of valid responses was written does it
# replace tests/testthat/api/; the previous fixtures are kept in
# tests/testthat/api.bak/ until the next successful run and are put back if
# the replacement fails. A network failure therefore leaves the current
# fixtures untouched.

pkgload::load_all(".", quiet = TRUE)

destino <- "tests/testthat/api"
backup <- "tests/testthat/api.bak"
tmp <- tempfile("fixtures_")
dir.create(tmp)

# Responses each call below must produce (data pages, field check, facets,
# localities).
esperadas <- 6L

httptest2::.mockPaths(tmp)
httptest2::capture_requests({
  mds_clear_cache()
  mds_data(
    c("qtd_familias_beneficiarias_bolsa_familia_i", "bpc_ben_i"),
    periods = c(202402, 202509),
    localities = c(2611606, 2607901)
  )
  mds_bpc_suas(periods = 202509, localities = 2611606)
  mds_periods("bpc_ben_i", localities = "PE")
  mds_localities(period = "202512")
  # Expected to fail: the recorded answer says the field has no document.
  res <- tryCatch(
    mds_data("campo_inexistente_i", periods = 202401, localities = "PE"),
    misocialr_error_validation = function(e) "rejected"
  )
  stopifnot(identical(res, "rejected"))
})

gravadas <- list.files(tmp, recursive = TRUE, full.names = TRUE)
if (length(gravadas) != esperadas) {
  stop("Recorded ", length(gravadas), " responses, expected ", esperadas,
       "; ", destino, " was not changed.")
}
# Each response must be a complete Solr answer, not an error page.
validas <- vapply(gravadas, function(f) {
  r <- tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE),
                error = function(e) NULL)
  is.list(r) && is.list(r$responseHeader) &&
    identical(as.integer(r$responseHeader$status), 0L) &&
    is.list(r$response)
}, logical(1))
if (!all(validas)) {
  stop("Invalid recorded response(s): ", paste(basename(gravadas[!validas]),
                                               collapse = ", "),
       "; ", destino, " was not changed.")
}

# Replace with a backup: the old fixtures are moved to `backup` and put back
# if any step fails. (Moving and copying are separate steps, so this is a
# replacement with rollback, not an atomic swap.)
restaurar <- function(msg) {
  unlink(destino, recursive = TRUE)
  if (dir.exists(backup) && !file.rename(backup, destino)) {
    stop(msg, " Could not restore ", destino, "; the previous fixtures are in ",
         backup, ".")
  }
  stop(msg, " The previous fixtures were restored.")
}
unlink(backup, recursive = TRUE)
if (dir.exists(destino) && !file.rename(destino, backup)) {
  stop("Could not move ", destino, " to ", backup, "; nothing was changed.")
}
if (!dir.create(destino, recursive = TRUE)) {
  restaurar(paste("Could not create", destino, "."))
}
ok <- file.copy(file.path(tmp, list.files(tmp)), destino, recursive = TRUE)
if (!all(ok) ||
      length(list.files(destino, recursive = TRUE)) != esperadas) {
  restaurar("Could not copy the new fixtures.")
}
message("Fixtures replaced: ", esperadas, " responses in ", destino,
        " (previous ones in ", backup, ").")
