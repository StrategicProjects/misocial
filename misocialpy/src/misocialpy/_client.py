"""HTTP layer for the MI Social API.

The MI Social API is an open Apache Solr ``select`` handler: every call is a
``q=*:*`` query narrowed with filter queries (``fq``), with paging
(``start``, ``rows``), field selection (``fl``) and facets.

Transient failures are retried (mirroring ``httr2::req_retry``) and errors
raise :class:`MdsError` with the Solr message when there is one.
"""

from __future__ import annotations

import math
from collections.abc import Mapping
from typing import Any

import requests
from requests.adapters import HTTPAdapter

try:  # urllib3 ships with requests; import path is stable
    from urllib3.util.retry import Retry
except ImportError:  # pragma: no cover
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

from . import _msg

MDS_BASE_URL = "https://aplicacoes.mds.gov.br/sagi/servicos/misocial"

_TIMEOUT = 180.0


def _user_agent() -> str:
    """User agent with the package version."""
    from . import __version__

    return f"misocialpy/{__version__} (Python package; {MDS_BASE_URL})"


# Seconds between retries grow as _BACKOFF * 2 ** (retry - 1); the first
# retry is immediate (urllib3).
_BACKOFF = 2.0


def set_timeout(seconds: float) -> None:
    """Set the timeout, in seconds, of every request (default 180).

    Must be a finite, strictly positive number; on error the previous timeout
    is kept.
    """
    global _TIMEOUT
    if (
        not isinstance(seconds, (int, float))
        or isinstance(seconds, bool)
        or not math.isfinite(seconds)
        or seconds <= 0
    ):
        raise ValueError("`seconds` must be a finite, positive number.")
    _TIMEOUT = float(seconds)


class MdsError(RuntimeError):
    """Base class of every misocialpy error."""


class HttpError(MdsError):
    """The request failed (transport or HTTP status). ``status`` is the HTTP
    status code, or ``None`` when no response arrived."""

    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


class ResponseError(MdsError):
    """The API answered, but the answer is incomplete or malformed."""


class DataConflictError(MdsError):
    """The API contradicts itself (two values for the same observation)."""


# A Retry-After header is obeyed, but never for more than this many seconds
# per try (the same cap as the R package).
_RETRY_AFTER_MAX = 30.0


class _CappedRetry(Retry):
    """urllib3 Retry whose Retry-After wait is capped."""

    def get_retry_after(self, response):
        wait = super().get_retry_after(response)
        return None if wait is None else min(wait, _RETRY_AFTER_MAX)


def _session() -> requests.Session:
    session = requests.Session()
    # 400 means the query itself is wrong (e.g. an undefined field): retrying
    # would only repeat the same answer. Connection failures (DNS, reset,
    # timeout) are retried too, within the same total.
    # urllib3 counts retries after the first request: 2 retries = 3 tries,
    # the same as max_tries = 3 in the R package.
    retry = _CappedRetry(
        total=2,
        connect=2,
        read=2,
        backoff_factor=_BACKOFF,
        status_forcelist=(429, 500, 502, 503, 504),
        # The query is sent by POST but only reads: retrying it is safe.
        allowed_methods=frozenset(["GET", "POST"]),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    session.headers.update({"User-Agent": _user_agent()})
    return session


def _http_error_hint(resp: requests.Response) -> str:
    """Explain an HTTP error, surfacing Solr's ``error.msg`` when present."""
    try:
        msg = resp.json()["error"]["msg"]
    except (ValueError, KeyError, TypeError):
        msg = None
    if msg:
        return f"HTTP error {resp.status_code}: {msg}"
    return f"HTTP error {resp.status_code}"


def mds_request(query: Mapping[str, Any] | None = None, label: str = "data") -> Any:
    """Build and execute a request to the MI Social API.

    Repeated parameters (several ``fq``) are given as a list under one key.
    """
    params = {"q": "*:*", "wt": "json"}
    params.update({k: v for k, v in (query or {}).items() if v is not None})

    _msg.step(f"Fetching {label} from MDS MI Social API...")
    try:
        # The query goes in the body (POST form): with many months, fields and
        # codes a GET URL passes the server limit (HTTP 414 measured at about
        # 8,000 characters). The Solr select handler answers both the same way.
        resp = _session().post(MDS_BASE_URL, data=params, timeout=_TIMEOUT)
    except requests.RequestException as exc:
        raise HttpError(
            f"Failed to access the MDS MI Social API.\n  x {exc}\n  i URL: {MDS_BASE_URL}"
        ) from exc

    if resp.status_code >= 400:
        raise HttpError(
            "Failed to access the MDS MI Social API.\n"
            f"  x {_http_error_hint(resp)}\n  i URL: {resp.url}",
            status=resp.status_code,
        )

    # The server labels its JSON as text/plain; requests does not check it.
    try:
        return resp.json()
    except ValueError as exc:
        raise ResponseError(
            "Unexpected response from the MI Social API.\n  x The body is not valid JSON."
        ) from exc
