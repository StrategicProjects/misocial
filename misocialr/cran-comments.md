## Submission: misocialr 0.4.1

This is an update of misocialr 0.4.0 (accepted 2026-10-31).

Changes in this version:

* Clear error when the MI Social API is unavailable: a server under
  maintenance redirects every request to a notice page or serves an HTML
  page from the API URL; both now raise a classed error saying the service
  is unavailable, instead of a JSON parser error.
* One author added to Authors@R (Julia Nascimento Barreto), already an
  author of the package's companion materials.
* As asked by the CRAN reviewer on acceptance of 0.4.0, single quotes in
  DESCRIPTION are now used only around software, package and API names
  ('Tidyverse', 'MI Social', 'R'); the quotes on MDS, SAGI, Cadastro Unico,
  Bolsa Familia, BPC, CRAS, CREAS, SUAS and tibbles were removed.

All examples that reach the network are wrapped in
`@examplesIf interactive()`; the test suite runs entirely offline against
recorded responses (httptest2 fixtures and a local webfakes server).

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* local: macOS (aarch64-apple-darwin), R 4.6.0
* win-builder: R-devel
* GitHub Actions: ubuntu-latest (release, oldrel-1, 4.1), windows-latest
  (release), macos-latest (release), plus one job with the minimum declared
  dependency versions
