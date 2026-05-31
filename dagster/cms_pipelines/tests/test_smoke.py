"""Smoke test for the Dagster definitions entrypoint."""

from cms_pipelines.definitions import defs

from dagster import Definitions


def test_definitions_load() -> None:
    """Calling the `@definitions` entrypoint returns a Definitions object."""
    result = defs()
    assert isinstance(result, Definitions)
