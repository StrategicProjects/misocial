#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang .data .env := %||%
## usethis namespace: end
NULL

.onLoad <- function(libname, pkgname) {
  ns <- asNamespace(pkgname)
  assign("mds_dictionary", read_extdata("dictionary.csv"), envir = ns)
  assign("mds_theme_table", read_extdata("themes.csv"), envir = ns)
}
