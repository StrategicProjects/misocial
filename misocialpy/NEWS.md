# misocialpy 0.4.0

Same changes as misocialr 0.4.0: paging by `cursorMark`, `nature` and
`nature_basis` columns in `mds_fields()`, corrected label of the Fomento
Rural `..._ano_f` field and `set_cache_ttl(seconds)`.

# misocialpy 0.3.1

Same fixes as misocialr 0.3.1 (details in `REVISAO_FINAL_2026-10-19.md` at
the repository root), plus the Python-specific ones:

* Results of `mds_periods()`, `mds_api_fields()` and `mds_localities()` are
  copies: editing a result no longer changes the cache (F1).
* `mds_drop_unpublished()`: a fractional period (`202401.9`) and a missing
  `field` (`pd.NA`) are errors; `today=None` is the only default (F3).
* `set_timeout()` requires a finite positive number and keeps the previous
  value on error (F7).
* Extras `test` (pytest, responses) and `dev` (plus ruff and build) (F8).
* Numpy scalars and integer-valued numbers (`26.0`) are accepted, as in R.
* Three attempts in total, as in R (previously 4); `Retry-After` capped at
  30 s; retries allowed on POST.
* `LICENSE` with the full MIT text (previously only the CRAN template).
* The `live` mark is registered in `conftest.py`: the suite behaves the
  same outside the project (tested against the wheel installed in a clean
  environment).

# misocialpy 0.3.0

Same fixes as misocialr 0.3.0 (details in `REVISAO_PROFUNDA_2026-10-19.md`
at the repository root): single response contract, no caching of incomplete
responses; `mds_localities()` paged and validated, with `period` and
`refresh`; `mds_drop_unpublished()` never deleting a non-zero value, with a
normalised period and `action="flag"`; identity and scalar value per
document; conflicts as `DataConflictError`; consistent paging; facets in
disjoint blocks; `refresh` and canonical cache keys; `HttpError`,
`ResponseError` and `DataConflictError`, all inheriting from `MdsError`
(and `ValidationError` also from `ValueError`); `storage_type`; local
validation with `validate=False`; warning for a municipality without
documents.

# misocialpy 0.2.1

Same fixes as misocialr 0.2.1 (details in `REVISAO_2026-10-19.md` at the
repository root): locality and period validated (empty, `None`, `NaN`,
non-integer, wrong check digit, invalid next to `"BR"`), text field as a
`ValidationError` (previously a `ValueError` without context), incomplete
or partial response as an `MdsError`, `mds_api_fields()` paged,
`mds_drop_unpublished()` with validation and `reference="brazil"`,
`set_timeout()` and `df.attrs["retrieved_at"]`. Minimum versions of pandas
and requests tested.

# misocialpy 0.2.0

Four new themes and shortcuts `mds_suas_rede()`, `mds_suas_financiamento()`,
`mds_pbf_condicionalidades()` and `mds_seguranca_alimentar()`.

# misocialpy 0.1.0

First version, a port of misocialr 0.1.0.
