# Releasing

Both packages live in this monorepo; each has its own tag pattern, and every
GitHub release triggers a Zenodo deposit under the repo's single Zenodo
concept, with metadata taken from `.zenodo.json` **in the tagged tree**
(templates in `.zenodo/`, swapped by `tools/release.sh`).

## misocialr (R)

1. Bump `Version:` in `misocialr/DESCRIPTION`; update `misocialr/NEWS.md`.
2. If vignettes changed: `Rscript vignettes/precompile.R` (live API) from
   `misocialr/` and commit the regenerated `.Rmd` and figures.
3. `R CMD build misocialr && R CMD check --as-cran misocialr_*.tar.gz`.
4. Submit to CRAN (`cran-comments.md` up to date); after acceptance, update
   `misocialr/CRAN-SUBMISSION` and add/refresh the CRAN version badge in
   `misocialr/README.md`.
5. `tools/release.sh misocialr X.Y.Z` (tags `vX.Y.Z` with the R Zenodo
   metadata in the tree).
6. `gh release create vX.Y.Z --title "misocialr X.Y.Z" --notes "..."` —
   this mints the Zenodo DOI for the version.

## misocialpy (Python)

1. Bump `version` in `misocialpy/pyproject.toml` and `__version__` in
   `src/misocialpy/__init__.py`; update `misocialpy/NEWS.md`.
2. `tools/release.sh misocialpy X.Y.Z` (tags `misocialpy-vX.Y.Z`). The tag
   push runs `.github/workflows/pypi.yaml`, which builds, checks and
   publishes to PyPI via trusted publishing.
3. `gh release create misocialpy-vX.Y.Z --title "misocialpy X.Y.Z"
   --notes "..."` — this mints the Zenodo DOI for the version.
4. Update the DOI badge in `misocialpy/README.md` to the new version DOI.

Notes

- Release tags are protected by a repo ruleset (no update/delete); to redo a
  tag, temporarily disable the ruleset in Settings → Rules.
- Cite a specific version by its version DOI; the concept DOI
  (10.5281/zenodo.23504084) covers the whole repository and resolves to the
  latest release of either package.
