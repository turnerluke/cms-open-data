"""Pytest bootstrap for the Dagster smoke test."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess

import pytest


DBT_PROJECT = Path(__file__).resolve().parents[3] / "dbt" / "cms_analytics"
MANIFEST = DBT_PROJECT / "target" / "manifest.json"


@pytest.fixture(scope="session", autouse=True)
def _dbt_manifest() -> None:
    """Generate `target/manifest.json` once per session if it's missing.

    `DbtProjectComponent` validates the manifest path at component-load
    time, so on a clean checkout `test_definitions_load` would fail with
    `DagsterDbtManifestNotFoundError`. Generate it on demand; locally
    this is a fast no-op when a prior `dbt parse` has already written it.
    """
    if MANIFEST.exists():
        return
    dbt_exe = shutil.which("dbt")
    if dbt_exe is None:
        pytest.skip("dbt CLI not on PATH; cannot bootstrap manifest")
    subprocess.run([dbt_exe, "deps", "--profiles-dir", "."], cwd=DBT_PROJECT, check=True)  # noqa: S603
    subprocess.run([dbt_exe, "parse", "--profiles-dir", ".", "--target", "ci"], cwd=DBT_PROJECT, check=True)  # noqa: S603
