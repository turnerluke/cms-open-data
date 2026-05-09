"""Shared fixtures for cms_api tests.

The retry-wait multiplier is forced to ``0`` so retry tests don't sleep.
"""

from collections.abc import Iterator

import pytest


@pytest.fixture(autouse=True)
def _zero_retry_wait(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Make tenacity sleeps zero across the suite."""
    monkeypatch.setenv("CMS_API_RETRY_WAIT_MULTIPLIER", "0")
    return
