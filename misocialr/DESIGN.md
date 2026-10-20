# Design

`misocialr` reproduces the architecture of `ibger` for a different source:
the MDS MI Social API, an open Apache Solr `select` handler with one document
per municipality x month (`codigo_ibge`, 6 digits; `anomes_s`, `YYYYMM`).

| Component | File | Responsibility |
| --- | --- | --- |
| HTTP core | `R/utils.R` | `mds_request()` (httr2, retries on 5xx/429 only, Solr error message surfaced), Solr filter builders |
| Dictionary | `R/fields.R`, `inst/extdata/*.csv` | Curated fields per theme; `mds_api_fields()` scans the live schema |
| Localities | `R/localidades.R` | Locality parsing, `ibge_code7()` (check digit + 9 exceptions), `mds_localities()` |
| Periods | `R/periodos.R` | Period parsing, `mds_periods()` via Solr facets (all values vs non-zero) |
| Retrieval | `R/dados.R` | Query plan (states + municipality chunks of 200), Solr paging (10,000 rows), long output |
| Validation + cache | `R/validacao.R` | Field checks, session cache, `mds_clear_cache()` |
| Publication rule | `R/publicacao.R` | `mds_drop_unpublished()` |

Decisions that differ from `ibger`, and why:

- **`value` is numeric.** IBGE encodes missingness in special strings, so
  `ibger` keeps `value` as character. MI Social returns JSON numbers and
  encodes absence by leaving the field out of the document, so absent fields
  simply produce no row.
- **Zeros are not always zeros.** The API returns `0` for months not yet
  published. Rather than silently dropping them, `mds_data()` returns what was
  published and `mds_drop_unpublished()` applies the rule explicitly (same
  rule as the BDE collector `etl/fontes/coletores/mds.R`).
- **Field validation asks for data, not schema.** The Solr schema has dynamic
  fields (`*_i`, `*_f`, ...), so any suffixed name is "defined". A field is
  accepted when at least one document has it (`numFound > 0`).
- **The server labels JSON as `text/plain`**, so responses are parsed with
  `check_type = FALSE`.
- **Labels are in Portuguese**, as the source; the dictionary lives in CSV so
  that R code stays ASCII and the Python sibling reads the same file.
- **Fail loudly on inputs that would widen or narrow the query.** An empty
  locality vector would mean "no filter", i.e. the whole country; a wrong
  check digit would silently become another municipality. Both are errors
  (0.2.1), as are text fields, whose values would otherwise become `NA` and
  vanish from the long output.
- **An empty page is not the end.** Paging stops only when `numFound` is
  reached; an empty page before that, Solr's `partialResults` or a response
  without `response` is an error.
- **Unpublished months can be judged by the whole country.**
  `mds_drop_unpublished(reference = "brazil")` reads the last month with a
  non-zero value from `mds_periods()`, so a small selection keeps its
  legitimate trailing zeros.
- **One response contract, checked before anything else (0.3.0).** Data
  pages, counts and facets go through `check_response()` (`R/resposta.R`)
  before they are interpreted or cached; then every document must carry a
  valid municipality and month and at most one value per field. A failure of
  the source can therefore never become "no data" for the rest of the
  session, nor shift a value to another municipality.
- **Repetition is fine, contradiction is not.** Observations repeated with
  the same value are dropped; different values for the same key are a
  `misocialr_error_conflict`.
- **Classification before deletion.** `mds_drop_unpublished()` never removes
  a non-zero value, re-reads a contradictory national reference, and can
  only flag (`action = "flag"`), because inferring publication from zeros is
  a heuristic, not an official date.
- **POST, not GET (0.3.1).** The Solr select handler answers a form POST
  exactly like a GET, and a long GET URL is refused with HTTP 414 (measured
  at about 8,000 characters). Municipality codes are still split in blocks
  of 200 to keep each filter small.
- **Retries are tested against a real server.** httr2's mocked responses
  and Python's `responses` return before the retry loop, so the retry tests
  use a local HTTP server (`webfakes` in R, `http.server` in Python). Both
  packages make 3 tries in total.
- **Behaviour parity is tested, not assumed.** `tests/testthat/paridade/
  casos.json` lists inputs and expected outputs or error classes; both test
  suites run it (the Python copy is kept by `sincronizar_python.py`).
- **Paging with `cursorMark` (0.4.0).** Pages are walked by the sort key
  (`id`), so documents added or removed while reading cannot shift them; a
  changing total and repeated ids are still errors, and reading stops at
  `numFound` without an extra request.
- **Nature with its basis (0.4.0).** Each field says how it may be summed
  and whether that was measured on the monthly series or inferred. An
  inferred nature is a default to check, not a fact.
