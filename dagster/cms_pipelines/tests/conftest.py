"""Pytest bootstrap for the Dagster tests.

Besides the dbt-manifest bootstrap, an autouse fixture isolates vintage
capture: extraction assets write vintage sidecars as a side effect, so
without isolation any asset materialization in tests would fetch real
upstream metadata and overwrite the live sidecars under the repo's
``data/raw/_vintages/``.
"""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess

from cms_api import DatasetSpec, DatasetVintage, local_vintage
from cms_pipelines.defs.cms import vintage_sidecar
from cms_pipelines.defs.resources import CMS_RAW_ROOT_ENV

import pytest


DBT_PROJECT = Path(__file__).resolve().parents[3] / "dbt" / "cms_analytics"
MANIFEST = DBT_PROJECT / "target" / "manifest.json"


@pytest.fixture(autouse=True)
def _isolated_vintage_capture(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """Point sidecar writes at ``tmp_path`` and stub the metadata fetch.

    ``CMS_RAW_ROOT`` is redirected so no test touches the repo's real
    ``data/raw/``, and `capture_dataset_vintage`'s fetch is replaced with
    an offline capture-time-only vintage so asset materializations never
    hit the network. Tests that care about either knob (e.g.
    ``test_resources``) still override it per-test via their own
    ``monkeypatch`` calls.
    """
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))

    def _offline_fetch(spec: DatasetSpec) -> DatasetVintage:
        return local_vintage(spec.key, spec.source, dataset_id=spec.dataset_id)

    monkeypatch.setattr(vintage_sidecar, "fetch_dataset_vintage", _offline_fetch)


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
