"""Shared HTTP client construction and retry policy.

All public clients in this package go through `request_json`, which wraps an
`httpx.Client` call in a tenacity retry loop. Transient failures (network
errors, HTTP 429, HTTP 5xx) are retried with exponential backoff; everything
else surfaces immediately so callers don't silently swallow bad requests.

When a 429 response carries an integer-seconds ``Retry-After`` header the
retry loop honours it (clamped to the wait cap) instead of using the
exponential schedule — CMS's data.cms.gov endpoints emit ``Retry-After`` when
the per-IP rate-limit window is active, and sleeping for the server-suggested
duration is the only way to survive it on shared egress IPs (e.g.
GitHub-hosted runners) where multiple concurrent clients keep the budget
drained. HTTP-date form ``Retry-After`` values are treated as absent — CMS
uses the integer form and parsing calendar dates from a rate-limiter header
is not worth the surface area.

Defaults are tunable via environment variables so pipelines can adjust
behaviour without code changes:

- ``CMS_API_TIMEOUT`` — request timeout in seconds (default ``30``).
- ``CMS_API_RETRY_MAX_ATTEMPTS`` — total tries including the first
  (default ``5``).
- ``CMS_API_RETRY_WAIT_MULTIPLIER`` — exponential-backoff multiplier in
  seconds (default ``0.5``); the test suite sets this to ``0`` for speed.
- ``CMS_API_RETRY_WAIT_MAX`` — cap on any single retry sleep in seconds
  (default ``8``). Also caps ``Retry-After`` values so a hostile or
  bugged server can't stall the pipeline indefinitely.
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING

import httpx
from tenacity import RetryCallState, retry, retry_if_exception, stop_after_attempt, wait_exponential


if TYPE_CHECKING:
    from collections.abc import Callable, Mapping

    from ._types import JsonValue

    WaitCallable = Callable[[RetryCallState], float]


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


def _parse_retry_after_seconds(response: httpx.Response) -> float | None:
    """Return the ``Retry-After`` header as seconds, or ``None`` if absent/unparseable.

    Only the integer-seconds form of RFC 9110 is honoured. HTTP-date values
    are treated as absent — CMS emits the integer form and this keeps the
    parser tiny.
    """
    raw = response.headers.get("Retry-After")
    if raw is None:
        return None
    try:
        seconds = float(raw.strip())
    except ValueError:
        return None
    if seconds < 0:
        return None
    return seconds


def _make_wait(multiplier: float, wait_max: float) -> WaitCallable:
    """Build the tenacity wait callable used by ``request_json``.

    Falls back to exponential backoff for every retry case except a 429
    that carries a parseable integer-seconds ``Retry-After``, in which case
    the header value (clamped to ``wait_max``) is returned instead.
    """
    exponential = wait_exponential(multiplier=multiplier, min=0, max=wait_max)

    def _wait(retry_state: RetryCallState) -> float:
        outcome = retry_state.outcome
        if outcome is not None and outcome.failed:
            exc = outcome.exception()
            if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code == _HTTP_TOO_MANY_REQUESTS:
                retry_after = _parse_retry_after_seconds(exc.response)
                if retry_after is not None:
                    return min(retry_after, wait_max)
        return exponential(retry_state)

    return _wait


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
    429 responses with an integer ``Retry-After`` header sleep for that
    interval (clamped to the wait cap) instead. Everything else (4xx,
    JSON-decode errors) raises immediately. The retry knobs are read from
    the environment on every call so tests can dial them down via
    ``monkeypatch.setenv`` without re-importing the module.
    """
    max_attempts = _env_int("CMS_API_RETRY_MAX_ATTEMPTS", DEFAULT_RETRY_MAX_ATTEMPTS)
    wait_multiplier = _env_float("CMS_API_RETRY_WAIT_MULTIPLIER", DEFAULT_RETRY_WAIT_MULTIPLIER)
    wait_max = _env_float("CMS_API_RETRY_WAIT_MAX", DEFAULT_RETRY_WAIT_MAX)

    @retry(
        retry=retry_if_exception(_is_transient),
        stop=stop_after_attempt(max_attempts),
        wait=_make_wait(wait_multiplier, wait_max),
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
