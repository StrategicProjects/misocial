# MI Social clients

R and Python clients for the **MI Social** API (Matriz de Informação
Social) of the Brazilian Ministry of Development and Social Assistance
(MDS/SAGI): <https://aplicacoes.mds.gov.br/sagi/servicos/misocial>.

Monthly municipal series of the Cadastro Único, the Bolsa Família programme
and its conditionalities, the BPC benefit, the social assistance network
(SUAS) and its funding, and food security programmes — as tidy long-format
tables.

| Package | Language | Docs |
| --- | --- | --- |
| [`misocialr`](misocialr/) | R (tibbles, httr2) | [README](misocialr/README.md), [NEWS](misocialr/NEWS.md) |
| [`misocialpy`](misocialpy/) | Python (pandas, requests) | [README](misocialpy/README.md), [NEWS](misocialpy/NEWS.md) |

The two packages expose the same 16 functions, name by name, read the same
field dictionary and are tested against the same recorded API responses;
`sincronizar_python.py --check` verifies that the shared files are
identical, and 65 shared behaviour cases
(`misocialr/tests/testthat/paridade/casos.json`) keep validation and error
behaviour in parity.

## License

MIT, see each package's LICENSE file.
