# Precompile the network-dependent vignettes.
#
# The vignettes query the live MI Social API, so they cannot be built on CRAN
# or CI. As in ibger (rOpenSci pattern), the executable source lives in
# *.Rmd.orig; this script knits it locally into the *.Rmd that ships with the
# package, with output and figures baked in. Run it from the package root
# whenever a .Rmd.orig changes, and commit the regenerated .Rmd and the
# bolsa-familia-*.png figures.
#
# Usage: Rscript vignettes/precompile.R

vignettes <- c("getting-started", "api-concepts", "bolsa-familia")

withr::with_dir("vignettes", {
  for (v in vignettes) {
    knitr::knit(paste0(v, ".Rmd.orig"), output = paste0(v, ".Rmd"))
  }
})
