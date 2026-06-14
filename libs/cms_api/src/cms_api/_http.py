"""Shared HTTP client construction and retry policy.

All public clients in this package go through `request_json`, which wraps an
`httpx.Client` call in a tenacity retry loop. Transient failures (network
errors, HTTP 429, HTTP 5xx) are retried with exponential backoff; everything
else surfaces immediately so callers don't silently swallow bad requests.

Defaults are tunable via environment variables so pipelines can adjust
behaviour without code changes:

- ``CMS_API_TIMEOUT`` — request timeout in seconds (default ``30``).
- ``CMS_API_RETRY_MAX_ATTEMPTS`` — total tries including the first
  (default ``5``).
- ``CMS_API_RETRY_WAIT_MULTIPLIER`` — exponential-backoff multiplier in
  seconds (default ``0.5``); the test suite sets this to ``0`` for speed.
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING

import httpx
from tenacity import retry, retry_if_exception, stop_after_attempt, wait_exponential


if TYPE_CHECKING:
    from collections.abc import Mapping

    from ._types import JsonValue


DEFAULT_TIMEOUT_SECONDS = 30.0
DEFAULT_USER_AGENT = "cms-api/0.1 (+https://github.com/turnerluke/cms-open-data)"
DEFAULT_RETRY_MAX_ATTEMPTS = 5
DEFAULT_RETRY_WAIT_MULTIPLIER = 0.5
DEFAULT_RETRY_WAIT_MAX = 8.0

_HTTP_TOO_MANY_REQUESTS = 429
_HTTP_SERVER_ERROR_FLOOR = 500
_HTTP_SERVER_ERROR_CEIL = 600


def _is_transient(exc: BaseException) -> bool:
    """Return True for exceptions worth retrying.

    Network/transport errors and HTTP 429 / 5xx are considered transient.
    Client-side 4xx (other than 429) bubble up unchanged.
    """
    if isinstance(exc, httpx.TransportError):
        return True
    if isinstance(exc, httpx.HTTPStatusError):
        status = exc.response.status_code
        return status == _HTTP_TOO_MANY_REQUESTS or _HTTP_SERVER_ERROR_FLOOR <= status < _HTTP_SERVER_ERROR_CEIL
    return False


def _env_float(name: str, default: float) -> float:
    """Read a float from the environment, falling back to ``default`` if unset/invalid."""
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    """Read an int from the environment, falling back to ``default`` if unset/invalid."""
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def build_client(
    *,
    base_url: str,
    headers: Mapping[str, str] | None = None,
    timeout: float | None = None,
) -> httpx.Client:
    """Construct an `httpx.Client` with sane defaults for CMS-style JSON APIs.

    Caller owns the client and is responsible for closing it (use ``with``
    or ``client.close()``).
    """
    final_headers: dict[str, str] = {"User-Agent": DEFAULT_USER_AGENT, "Accept": "application/json"}
    if headers:
        final_headers.update(headers)

    resolved_timeout = timeout if timeout is not None else _env_float("CMS_API_TIMEOUT", DEFAULT_TIMEOUT_SECONDS)
    return httpx.Client(base_url=base_url, headers=final_headers, timeout=resolved_timeout)


def request_json(
    client: httpx.Client,
    method: str,
    url: str,
    *,
    params: Mapping[str, str] | None = None,
) -> JsonValue:
    """Issue an HTTP request and return parsed JSON.

    Retries on transport errors and HTTP 429/5xx with exponential backoff;
    everything else (4xx, JSON-decode errors) raises immediately. The retry
    knobs are read from the environment on every call so tests can dial them
    down via ``monkeypatch.setenv`` without re-importing the module.
    """
    max_attempts = _env_int("CMS_API_RETRY_MAX_ATTEMPTS", DEFAULT_RETRY_MAX_ATTEMPTS)
    wait_multiplier = _env_float("CMS_API_RETRY_WAIT_MULTIPLIER", DEFAULT_RETRY_WAIT_MULTIPLIER)

    @retry(
        retry=retry_if_exception(_is_transient),
        stop=stop_after_attempt(max_attempts),
        wait=wait_exponential(multiplier=wait_multiplier, min=0, max=DEFAULT_RETRY_WAIT_MAX),
        reraise=True,
    )
    def _do() -> JsonValue:
        response = client.request(method, url, params=dict(params) if params else None)
        response.raise_for_status()
        # httpx.Response.json() returns Any; rebind through a typed local so
        # JsonValue propagates out instead of silently widening to Any.
        parsed: JsonValue = response.json()
        return parsed

    # tenacity's @retry decorator drops the inner function's return type;
    # rebind again at the call site for the same reason.
    result: JsonValue = _do()
    return result
