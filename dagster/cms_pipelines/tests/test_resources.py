"""Tests for the shared resource registration."""

from pathlib import Path

from cms_pipelines.defs.resources import CMS_RAW_ROOT_ENV, resolve_raw_root, shared_resources

from dagster import Definitions

import pytest


def test_resolve_raw_root_uses_env_var_when_set(monkeypatch: pytest.MonkeyPatch) -> None:
    """When `CMS_RAW_ROOT` is set, it wins over the repo-relative default."""
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, "/tmp/custom_raw")  # noqa: S108 -- test path

    assert resolve_raw_root() == "/tmp/custom_raw"  # noqa: S108 -- test path


def test_resolve_raw_root_falls_back_to_repo_default(monkeypatch: pytest.MonkeyPatch) -> None:
    """Without the env var, the default points at ``<repo>/data/raw``.

    A weaker ``endswith('data/raw')`` check would accept ``<repo>/dagster/
    data/raw`` too — exactly the off-by-one regression this test now
    guards against. dbt's ``external_location`` resolves ``data/raw/``
    against the actual repo root, so the IO manager must write there.
    """
    monkeypatch.delenv(CMS_RAW_ROOT_ENV, raising=False)

    # This test file is at <repo>/dagster/cms_pipelines/tests/test_resources.py,
    # so <repo> is three directories up.
    expected_repo_root = Path(__file__).resolve().parents[3]
    expected = expected_repo_root / "data" / "raw"

    assert Path(resolve_raw_root()) == expected


def test_shared_resources_registers_parquet_io_manager() -> None:
    """The `@definitions` factory exposes the `parquet_io_manager` resource."""
    defs = shared_resources()

    assert isinstance(defs, Definitions)
    assert defs.resources is not None
    assert "parquet_io_manager" in defs.resources
