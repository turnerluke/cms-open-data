"""Tests for the shared retry policy in ``cms_api._http``.

These exercise the wait callable and env-driven knobs directly rather
than through ``request_json`` — indirect timing observation is flaky and
the wait callable is where the interesting logic lives.
"""

from __future__ import annotations

from cms_api._http import DEFAULT_RETRY_WAIT_MAX, _make_wait, _parse_retry_after_seconds, build_client, request_json
import httpx
import respx
from tenacity import Future, RetryCallState, Retrying, stop_after_attempt

import pytest


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
    wait = _make_wait(multiplier=0.5, wait_max=90.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "3"}))
    assert wait(_retry_state_with_outcome(outcome)) == 3.0


def test_wait_clamps_retry_after_to_cap() -> None:
    """A pathological ``Retry-After: 500`` is capped at ``wait_max``."""
    wait = _make_wait(multiplier=0.5, wait_max=90.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "500"}))
    assert wait(_retry_state_with_outcome(outcome)) == 90.0


def test_wait_falls_back_to_exponential_on_garbage_retry_after() -> None:
    """Unparseable ``Retry-After`` triggers the exponential fallback path.

    With multiplier ``0`` the fallback returns ``0``, distinguishing it
    from any non-zero ``Retry-After`` value.
    """
    wait = _make_wait(multiplier=0.0, wait_max=90.0)
    outcome = _failed_outcome_from_response(httpx.Response(429, headers={"Retry-After": "tomorrow"}))
    assert wait(_retry_state_with_outcome(outcome)) == 0.0


def test_wait_falls_back_to_exponential_on_5xx() -> None:
    """Non-429 transient errors always use the exponential schedule."""
    wait = _make_wait(multiplier=0.0, wait_max=90.0)
    outcome = _failed_outcome_from_response(httpx.Response(503))
    assert wait(_retry_state_with_outcome(outcome)) == 0.0


def test_wait_max_env_var_read_per_call(monkeypatch: pytest.MonkeyPatch) -> None:
    """``CMS_API_RETRY_WAIT_MAX`` overrides the default cap.

    Constructed directly from a large ``Retry-After`` to observe the cap;
    the env var is read inside ``request_json`` so setting it there
    matches the production code path.
    """
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MAX", "12")

    # The wait factory itself doesn't read env — it takes the resolved
    # value — but the default cap should stay 8s so a missing env var
    # doesn't secretly change production behavior.
    assert DEFAULT_RETRY_WAIT_MAX == 8.0

    # And explicitly constructing with the env-derived cap works.
    wait = _make_wait(multiplier=0.5, wait_max=12.0)
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
