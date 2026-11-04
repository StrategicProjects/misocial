# MI Social clients

<!-- badges: start -->
![License](https://img.shields.io/badge/license-MIT-darkviolet.svg)
[![R-CMD-check](https://github.com/StrategicProjects/misocial/actions/workflows/misocialr.yaml/badge.svg)](https://github.com/StrategicProjects/misocial/actions/workflows/misocialr.yaml)
[![misocialpy](https://github.com/StrategicProjects/misocial/actions/workflows/misocialpy.yaml/badge.svg)](https://github.com/StrategicProjects/misocial/actions/workflows/misocialpy.yaml)
[![CRAN status](https://www.r-pkg.org/badges/version/misocialr)](https://CRAN.R-project.org/package=misocialr)
[![PyPI](https://img.shields.io/pypi/v/misocialpy.svg)](https://pypi.org/project/misocialpy/)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23504084.svg)](https://doi.org/10.5281/zenodo.23504084)
<!-- badges: end -->

R and Python clients for the **MI Social** API (Matriz de Informação
Social) of the Brazilian Ministry of Development and Social Assistance
(MDS/SAGI): <https://aplicacoes.mds.gov.br/sagi/servicos/misocial>.

Monthly municipal series of the Cadastro Único, the Bolsa Família programme
and its conditionalities, the BPC benefit, the social assistance network
(SUAS) and its funding, and food security programmes — as tidy long-format
tables.

| Package | Language | Install | DOI | Docs |
| --- | --- | --- | --- | --- |
| [`misocialr`](misocialr/) | R (tibbles, httr2) | [CRAN](https://CRAN.R-project.org/package=misocialr): `install.packages("misocialr")` | [10.5281/zenodo.23838960](https://doi.org/10.5281/zenodo.23838960) | [site](https://strategicprojects.github.io/misocial/), [README](misocialr/README.md), [NEWS](misocialr/NEWS.md) |
| [`misocialpy`](misocialpy/) | Python (pandas, requests) | [PyPI](https://pypi.org/project/misocialpy/): `pip install misocialpy` | [10.5281/zenodo.23945390](https://doi.org/10.5281/zenodo.23945390) | [README](misocialpy/README.md), [NEWS](misocialpy/NEWS.md) |

The DOI badge above is the concept DOI of the repository, which always
resolves to the latest release of either package; cite the per-package
DOIs in the table for a specific version.

The two packages expose the same 16 functions, name by name, read the same
field dictionary and are tested against the same recorded API responses;
`sincronizar_python.py --check` verifies that the shared files are
identical, and 65 shared behaviour cases
(`misocialr/tests/testthat/paridade/casos.json`) keep validation and error
behaviour in parity.

## License

MIT, see each package's LICENSE file.
