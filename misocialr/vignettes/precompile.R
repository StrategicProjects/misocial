# Precompile the network-dependent vignette.
#
# The vignette queries the live MI Social API, so it cannot be built on CRAN
# or CI. As in ibger (rOpenSci pattern), the executable source lives in
# *.Rmd.orig; this script knits it locally into the *.Rmd that ships with the
# package, with the output baked in. Run it from the package root whenever a
# .Rmd.orig changes.
#
# Usage: Rscript vignettes/precompile.R

vignettes <- c("getting-started")

withr::with_dir("vignettes", {
  for (v in vignettes) {
    knitr::knit(paste0(v, ".Rmd.orig"), output = paste0(v, ".Rmd"))
  }
})
