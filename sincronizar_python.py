"""Copia do pacote R para o Python o dicionário e as respostas gravadas.

    python3 sincronizar_python.py          (da pasta MDSr/)
    python3 sincronizar_python.py --check  (só confere; sai com erro se diferir)

O dicionário nasce em misocialr/inst/extdata/, os casos de paridade em
misocialr/tests/testthat/paridade/casos.json e as fixtures em
misocialr/tests/testthat/api/ (Rscript data-raw/record_fixtures.R). Cada
fixture do R tem nome de hash; aqui ela é identificada pelos filtros (fq) da
consulta gravada na própria resposta e recebe o nome que
misocialpy/tests/conftest.py espera (tabela ROUTES).
"""
from __future__ import annotations

import ast
import json
import shutil
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
R_EXTDATA = RAIZ / "misocialr/inst/extdata"
PY_DATA = RAIZ / "misocialpy/src/misocialpy/data"
R_API = RAIZ / "misocialr/tests/testthat/api"
PY_FIXTURES = RAIZ / "misocialpy/tests/fixtures"
CONFTEST = RAIZ / "misocialpy/tests/conftest.py"
R_PARIDADE = RAIZ / "misocialr/tests/testthat/paridade/casos.json"


def rotas() -> dict[tuple, str]:
    """Lê a tabela ROUTES do conftest.py sem importá-lo."""
    arvore = ast.parse(CONFTEST.read_text(encoding="utf-8"))
    for no in arvore.body:
        if isinstance(no, ast.Assign) and getattr(no.targets[0], "id", "") == "ROUTES":
            return ast.literal_eval(no.value)
    sys.exit("ROUTES não encontrado em conftest.py")


def chave(resposta: Path) -> tuple:
    fq = json.loads(resposta.read_text(encoding="utf-8"))["responseHeader"]["params"]["fq"]
    return tuple([fq] if isinstance(fq, str) else fq)


def main() -> int:
    so_conferir = "--check" in sys.argv
    pares = [(R_EXTDATA / n, PY_DATA / n) for n in ("dictionary.csv", "themes.csv")]
    # Behaviour cases shared by the two test suites.
    pares.append((R_PARIDADE, PY_FIXTURES / "parity_cases.json"))

    esperadas = rotas()
    gravadas: dict[tuple, Path] = {}
    for p in sorted(R_API.rglob("*.txt")):
        k = chave(p)
        # Two responses with the same filters (pages of one query, for
        # instance) would overwrite each other silently.
        if k in gravadas:
            print(f"Duas fixtures com os mesmos filtros {k}:\n  {gravadas[k]}\n  {p}")
            return 1
        gravadas[k] = p
    faltam = [k for k in esperadas if k not in gravadas]
    if faltam:
        print("Fixtures exigidas pelo conftest.py e ausentes no R:", *faltam, sep="\n  ")
        return 1
    pares += [(gravadas[k], PY_FIXTURES / nome) for k, nome in esperadas.items()]
    sobras = sorted(set(gravadas) - set(esperadas))
    if sobras:
        print(f"Aviso: {len(sobras)} fixture(s) do R sem uso no Python:", *sobras, sep="\n  ")

    diferentes = [d for o, d in pares if not d.exists() or o.read_bytes() != d.read_bytes()]
    if so_conferir:
        for d in diferentes:
            print("difere:", d.relative_to(RAIZ))
        print(f"{len(pares)} arquivos conferidos, {len(diferentes)} diferente(s).")
        return 1 if diferentes else 0

    for o, d in pares:
        if d in diferentes:
            shutil.copyfile(o, d)
            print("copiado:", d.relative_to(RAIZ))
    print(f"{len(pares)} arquivos, {len(diferentes)} atualizado(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
