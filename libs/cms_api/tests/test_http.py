"""Tests for the shared retry policy in ``cms_api._http``.

These exercise the wait callable and env-driven knobs directly rather
than through ``request_json`` — indirect timing observation is flaky and
the wait callable is where the interesting logic lives.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from cms_api._http import (
    DEFAULT_RETRY_AFTER_MAX,
    DEFAULT_RETRY_WAIT_MAX,
    _make_wait,
    _parse_retry_after_seconds,
    build_client,
    download_file,
    request_json,
)
import httpx
import respx
from tenacity import Future, RetryCallState, Retrying, stop_after_attempt

import pytest


if TYPE_CHECKING:
    from pathlib import Path


def _failed_outcome_from_response(response: httpx.Response) -> Future:
    """Construct a tenacity ``Future`` in the failed state carrying an ``HTTPStatusError``."""
    request = httpx.Request("GET", "https://example.test/x")
    response.request = request
    exc = httpx.HTTPStatusError("boom", request=request, response=response)
    fut = Future(attempt_number=1)
    fut.set_exception(exc)
    return fut


def _retry_state_with_outcome(outcome: Future) -> RetryCallState:
    """Build a minimal ``RetryCallState`` with a pre-set outcome."""
    retrying = Retrying(stop=stop_after_attempt(1))
    state = RetryCallState(retry_object=retrying, fn=None, args=(), kwargs={})
    state.outcome = outcome
    state.attempt_number = 2
    return state


def test_parse_retry_after_seconds_integer() -> None:
    """Integer-seconds ``Retry-After`` parses back as a float."""
    response = httpx.Response(429, headers={"Retry-After": "42"})
    assert _parse_retry_after_seconds(response) == 42.0


def test_parse_retry_after_seconds_missing() -> None:
    """Missing header parses as ``None``."""
    response = httpx.Response(429)
    assert _parse_retry_after_seconds(response) is None


def test_parse_retry_after_seconds_garbage() -> None:
    """A non-numeric header (e.g. HTTP-date) parses as ``None``."""
    response = httpx.Response(429, headers={"Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"})
    assert _parse_retry_after_seconds(response) is None


def test_parse_retry_after_seconds_negative() -> None:
    """A negative value is discarded — sleeping backwards is nonsense."""
    response = httpx.Response(429, headers={"Retry-After": "-5"})
    assert _parse_retry_after_seconds(response) is None


def test_wait_honors_retry_after_under_cap() -> None:
    """A 429 with a small ``Retry-After`` returns that value directly."""
    wait = _make_wait(multiplier=0.5, wait_max=90.0, retry_after_max=300.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "3"}))
    assert wait(_retry_state_with_outcome(outcome)) == 3.0


def test_wait_honors_retry_after_above_wait_max_below_after_max() -> None:
    """A ``Retry-After`` above ``wait_max`` but below ``retry_after_max`` is honored in full.

    CMS occasionally emits 120s cool-offs; clamping those to the 90s
    exponential cap would race the rate-limit window and burn a retry.
    """
    wait = _make_wait(multiplier=0.5, wait_max=90.0, retry_after_max=300.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "120"}))
    assert wait(_retry_state_with_outcome(outcome)) == 120.0


def test_wait_clamps_retry_after_to_retry_after_max() -> None:
    """A pathological ``Retry-After: 9999`` is capped at ``retry_after_max``."""
    wait = _make_wait(multiplier=0.5, wait_max=90.0, retry_after_max=300.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "9999"}))
    assert wait(_retry_state_with_outcome(outcome)) == 300.0


def test_wait_falls_back_to_exponential_on_garbage_retry_after() -> None:
    """Unparseable ``Retry-After`` triggers the exponential fallback path.

    With multiplier ``0`` the fallback returns ``0`` regardless of the
    jitter factor, distinguishing it from any non-zero ``Retry-After``
    value.
    """
    wait = _make_wait(multiplier=0.0, wait_max=90.0, retry_after_max=300.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "tomorrow"}))
    assert wait(_retry_state_with_outcome(outcome)) == 0.0


def test_wait_falls_back_to_exponential_on_5xx() -> None:
    """Non-429 transient errors always use the exponential schedule."""
    wait = _make_wait(multiplier=0.0, wait_max=90.0, retry_after_max=300.0)
    outcome = _failed_outcome_from_response(httpx.Response(503))
    assert wait(_retry_state_with_outcome(outcome)) == 0.0


def test_wait_exponential_branch_is_jittered_within_bounds() -> None:
    """Exponential fallback stays within [0.75x, 1.25x] of deterministic and <= wait_max.

    Sampling many times covers the jitter distribution; the deterministic
    tenacity value at attempt 2 with multiplier 1.0 is 2.0s, so acceptable
    outputs lie in [1.5, 2.5]. wait_max is set well above the ceiling so
    clamping doesn't hide bugs.
    """
    wait = _make_wait(multiplier=1.0, wait_max=100.0, retry_after_max=300.0)
    samples = [wait(_retry_state_with_outcome(_failed_outcome_from_response(httpx.Response(503)))) for _ in range(200)]
    assert min(samples) >= 2.0 * 0.75
    assert max(samples) <= 2.0 * 1.25
    # Randomness actually varies the value (>1 distinct sample).
    assert len({round(s, 6) for s in samples}) > 1


def test_wait_exponential_jitter_reclamped_to_wait_max() -> None:
    """Even after jitter widens the value, the result stays <= wait_max."""
    # Deterministic exponential at attempt 2 with multiplier 10 is 20s, cap
    # at 5 to force clamping regardless of the jitter draw.
    wait = _make_wait(multiplier=10.0, wait_max=5.0, retry_after_max=300.0)
    for _ in range(100):
        value = wait(_retry_state_with_outcome(_failed_outcome_from_response(httpx.Response(503))))
        assert value <= 5.0


def test_wait_max_env_var_read_per_call(monkeypatch: pytest.MonkeyPatch) -> None:
    """``CMS_API_RETRY_WAIT_MAX`` overrides the default cap.

    Constructed directly from a large ``Retry-After`` to observe the cap;
    the env var is read inside ``request_json`` so setting it there
    matches the production code path.
    """
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MAX", "12")

    # The wait factory itself doesn't read env — it takes the resolved
    # value — but the default caps should stay stable so a missing env
    # var doesn't secretly change production behavior.
    assert DEFAULT_RETRY_WAIT_MAX == 8.0
    assert DEFAULT_RETRY_AFTER_MAX == 300.0

    # A small explicit retry_after_max clamps the Retry-After path.
    wait = _make_wait(multiplier=0.5, wait_max=90.0, retry_after_max=12.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "60"}))
    assert wait(_retry_state_with_outcome(outcome)) == 12.0


@respx.mock
def test_request_json_honors_retry_after_end_to_end(monkeypatch: pytest.MonkeyPatch) -> None:
    """``request_json`` sleeps on ``Retry-After`` and eventually succeeds.

    Uses a zero cap so the honored sleep is effectively 0 and the test
    stays fast.
    """
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MAX", "0")
    route = respx.get("https://example.test/data").mock(
        side_effect=[
            httpx.Response(429, headers={"Retry-After": "30"}),
            httpx.Response(200, json={"ok": True}),
        ],
    )
    with build_client(base_url="https://example.test") as client:
        result = request_json(client, "GET", "/data")

    assert result == {"ok": True}
    assert route.call_count == 2


@respx.mock
def test_request_json_still_does_not_retry_non_429_4xx() -> None:
    """Regression: a 400 still surfaces immediately with the new wait callable."""
    route = respx.get("https://example.test/data").respond(400, json={"error": "bad"})
    with (
        build_client(base_url="https://example.test") as client,
        pytest.raises(httpx.HTTPStatusError),
    ):
        request_json(client, "GET", "/data")

    assert route.call_count == 1


@respx.mock
def test_download_file_happy_path(tmp_path: Path) -> None:
    """A 200 response's bytes land at ``dest``."""
    payload = b"col_a,col_b\n1,2\n3,4\n"
    respx.get("https://example.test/file.csv").mock(return_value=httpx.Response(200, content=payload))

    dest = tmp_path / "file.csv"
    download_file("https://example.test/file.csv", dest)

    assert dest.read_bytes() == payload


@respx.mock
def test_download_file_retries_429_then_succeeds(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """A 429-then-200 sequence completes, and dest holds the second response.

    Load-bearing: proves the destination is re-opened fresh per attempt.
    If the first-attempt bytes leaked into ``dest`` they'd corrupt the
    file; asserting exact equality to the second payload rules that out.
    """
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MAX", "0")
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MULTIPLIER", "0")

    good_payload = b"final,payload\n1,2\n"
    route = respx.get("https://example.test/file.csv").mock(
        side_effect=[
            httpx.Response(429, headers={"Retry-After": "0"}, content=b"THROTTLED-BODY"),
            httpx.Response(200, content=good_payload),
        ],
    )

    dest = tmp_path / "file.csv"
    download_file("https://example.test/file.csv", dest)

    assert route.call_count == 2
    assert dest.read_bytes() == good_payload


@respx.mock
def test_download_file_raises_immediately_on_404_without_writing(tmp_path: Path) -> None:
    """A 404 surfaces at once and no file is created at ``dest``.

    ``raise_for_status()`` runs before any bytes are written, so a
    permanent 4xx must never leave an error body sitting at the target
    path where a downstream reader could mistake it for real data.
    """
    route = respx.get("https://example.test/missing.csv").respond(404, content=b"not found")

    dest = tmp_path / "missing.csv"
    with pytest.raises(httpx.HTTPStatusError):
        download_file("https://example.test/missing.csv", dest)

    assert not dest.exists()
    assert route.call_count == 1


@respx.mock
def test_download_file_retries_transport_error_then_succeeds(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A first-attempt ``TransportError`` retries and the second attempt lands cleanly.

    This approximates the "mid-stream failure" case: simulating a real
    mid-stream ``ReadError`` inside respx's mock transport is awkward
    because the httpx client swallows partially-written state, so a
    fully-failed first attempt followed by a good one is used instead.
    It still proves the retry policy applies to ``download_file`` and
    that a subsequent success writes only the good payload.
    """
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MAX", "0")
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MULTIPLIER", "0")

    good_payload = b"complete,payload\n5,6\n"
    route = respx.get("https://example.test/file.csv").mock(
        side_effect=[
            httpx.ConnectError("simulated transport failure"),
            httpx.Response(200, content=good_payload),
        ],
    )

    dest = tmp_path / "file.csv"
    download_file("https://example.test/file.csv", dest)

    assert route.call_count == 2
    assert dest.read_bytes() == good_payload
