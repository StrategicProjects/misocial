## Notes for the next update

misocialr 0.4.0 was accepted on 2026-10-31. The CRAN reviewer asked that,
in the next update, single quotes be used only around software, package and
API names, and removed from other terms. DESCRIPTION already follows this:
quotes remain only on 'Tidyverse', 'MI Social' and 'R'; the quotes on MDS,
SAGI, Cadastro Unico, Bolsa Familia, BPC, CRAS, CREAS, SUAS and tibbles were
removed. Mention this in the "Resubmission"/update notes of the next version.

## Submission: misocialr 0.4.0

This is a new submission. The package is a tidyverse-friendly client for
the MI Social API of the Brazilian Ministry of Development and Social
Assistance (MDS/SAGI).

All examples that reach the network are wrapped in
`@examplesIf interactive()`; the test suite runs entirely offline against
recorded responses (httptest2 fixtures and a local webfakes server).

## R CMD check results

0 errors | 0 warnings | 1 note

* New submission.

## Test environments

* local: macOS (aarch64-apple-darwin), R 4.6.0
* win-builder: R-devel
* GitHub Actions: ubuntu-latest (release, oldrel-1, 4.1), windows-latest
  (release), macos-latest (release), plus one job with the minimum declared
  dependency versions
