"""Tests for the cms raw-extraction resource registration."""

from cms_pipelines.defs.cms.resources import CMS_RAW_ROOT_ENV, _resolve_raw_root, cms_resources

from dagster import Definitions

import pytest


def test_resolve_raw_root_uses_env_var_when_set(monkeypatch: pytest.MonkeyPatch) -> None:
    """When `CMS_RAW_ROOT` is set, it wins over the repo-relative default."""
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, "/tmp/custom_raw")  # noqa: S108 -- test path

    assert _resolve_raw_root() == "/tmp/custom_raw"  # noqa: S108 -- test path


def test_resolve_raw_root_falls_back_to_repo_default(monkeypatch: pytest.MonkeyPatch) -> None:
    """Without the env var, the default points at the repo's `data/raw/` directory."""
    monkeypatch.delenv(CMS_RAW_ROOT_ENV, raising=False)

    resolved = _resolve_raw_root()

    assert resolved.endswith("data/raw")


def test_cms_resources_registers_io_manager() -> None:
    """The `@definitions` factory exposes the `cms_raw_io_manager` resource."""
    defs = cms_resources()

    assert isinstance(defs, Definitions)
    assert defs.resources is not None
    assert "cms_raw_io_manager" in defs.resources
