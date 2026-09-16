"""Tests for ``scripts/publish_dbt_run_results.py``.

Uses the same ``importlib.util.spec_from_file_location`` pattern as
``test_dbt_sources_in_sync.py`` because ``scripts/`` is not a package.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import duckdb

import pytest


_REPO_ROOT = Path(__file__).resolve().parents[1]
_SCRIPT = _REPO_ROOT / "scripts" / "publish_dbt_run_results.py"


def _load_publisher() -> object:
    """Import ``scripts/publish_dbt_run_results.py`` without adding scripts/ to sys.path."""
    spec = importlib.util.spec_from_file_location("publish_dbt_run_results", _SCRIPT)
    if spec is None or spec.loader is None:
        msg = f"Could not load module spec for {_SCRIPT}"
        raise RuntimeError(msg)
    module = importlib.util.module_from_spec(spec)
    sys.modules["publish_dbt_run_results"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def artifacts(tmp_path: Path) -> tuple[Path, Path, Path]:
    """Write minimal fake run_results.json + manifest.json + a scratch warehouse path."""
    run_results = {
        "metadata": {"generated_at": "2026-09-16T12:34:56.000000Z"},
        "results": [
            {
                "unique_id": "model.cms_analytics.dim_drug",
                "status": "success",
                "execution_time": 1.25,
                "failures": None,
                "message": "OK",
            },
            {
                "unique_id": "test.cms_analytics.not_null_dim_drug_drug_key.abc",
                "status": "pass",
                "execution_time": 0.10,
                "failures": 0,
                "message": None,
            },
            {
                "unique_id": "test.cms_analytics.relationships_dim_drug_fk.def",
                "status": "warn",
                "execution_time": 0.20,
                "failures": 7,
                "message": "Got 7 results, configured to warn if != 0",
            },
        ],
    }
    manifest = {
        "nodes": {
            "test.cms_analytics.not_null_dim_drug_drug_key.abc": {
                "depends_on": {"nodes": ["model.cms_analytics.dim_drug"]},
            },
            "test.cms_analytics.relationships_dim_drug_fk.def": {
                # A non-model parent (source) preceding a model parent — the
                # function should skip the source and pick the model.
                "depends_on": {
                    "nodes": [
                        "source.cms_analytics.cms_raw.cms_something",
                        "model.cms_analytics.dim_drug",
                    ],
                },
            },
        },
    }

    run_results_path = tmp_path / "run_results.json"
    manifest_path = tmp_path / "manifest.json"
    warehouse_path = tmp_path / "warehouse.duckdb"
    run_results_path.write_text(json.dumps(run_results), encoding="utf-8")
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    return run_results_path, manifest_path, warehouse_path


def test_publish_writes_expected_rows(artifacts: tuple[Path, Path, Path]) -> None:
    """End-to-end: publish then query the warehouse for row count and shape."""
    run_results_path, manifest_path, warehouse_path = artifacts
    publisher = _load_publisher()
    n = publisher.publish(run_results_path, manifest_path, warehouse_path)  # type: ignore[attr-defined]
    assert n == 3

    con = duckdb.connect(str(warehouse_path))
    try:
        total = con.execute("SELECT COUNT(*) FROM dbt_run_results").fetchone()
        assert total is not None
        assert total[0] == 3

        # Resource type derivation from the first dot-segment of unique_id.
        model_row = con.execute(
            """
            SELECT resource_type, name, parent_model, status, execution_time, failures
            FROM dbt_run_results
            WHERE unique_id = 'model.cms_analytics.dim_drug'
            """
        ).fetchone()
        assert model_row is not None
        assert model_row[0] == "model"
        assert model_row[1] == "dim_drug"
        assert model_row[2] is None
        assert model_row[3] == "success"
        assert model_row[4] == pytest.approx(1.25)
        assert model_row[5] is None

        # Test node attributed to its first model parent (source parent skipped).
        warn_row = con.execute(
            """
            SELECT resource_type, parent_model, status, failures
            FROM dbt_run_results
            WHERE unique_id = 'test.cms_analytics.relationships_dim_drug_fk.def'
            """
        ).fetchone()
        assert warn_row is not None
        assert warn_row[0] == "test"
        assert warn_row[1] == "model.cms_analytics.dim_drug"
        assert warn_row[2] == "warn"
        assert warn_row[3] == 7

        # generated_at parsed from run_results metadata. Compared in SQL:
        # fetching TIMESTAMPTZ values into Python requires pytz, which the
        # root-only CI env (plain `uv sync`) does not install.
        gen_row = con.execute(
            "SELECT DISTINCT generated_at = TIMESTAMPTZ '2026-09-16 12:34:56+00' FROM dbt_run_results"
        ).fetchall()
        assert gen_row == [(True,)]
    finally:
        con.close()


def test_publish_replaces_existing_table(artifacts: tuple[Path, Path, Path]) -> None:
    """Running twice should CREATE OR REPLACE rather than accumulate rows."""
    run_results_path, manifest_path, warehouse_path = artifacts
    publisher = _load_publisher()
    publisher.publish(run_results_path, manifest_path, warehouse_path)  # type: ignore[attr-defined]
    publisher.publish(run_results_path, manifest_path, warehouse_path)  # type: ignore[attr-defined]

    con = duckdb.connect(str(warehouse_path))
    try:
        total = con.execute("SELECT COUNT(*) FROM dbt_run_results").fetchone()
        assert total is not None
        assert total[0] == 3
    finally:
        con.close()


def test_publish_refuses_empty_results(tmp_path: Path) -> None:
    """An empty results array (aborted run) must fail fast, not publish an empty table."""
    run_results_path = tmp_path / "run_results.json"
    manifest_path = tmp_path / "manifest.json"
    warehouse_path = tmp_path / "warehouse.duckdb"
    run_results_path.write_text(json.dumps({"metadata": {}, "results": []}), encoding="utf-8")
    manifest_path.write_text(json.dumps({"nodes": {}}), encoding="utf-8")

    publisher = _load_publisher()
    with pytest.raises(ValueError, match="refusing to publish"):
        publisher.publish(run_results_path, manifest_path, warehouse_path)  # type: ignore[attr-defined]
    assert not warehouse_path.exists()


def test_main_cli(artifacts: tuple[Path, Path, Path], capsys: pytest.CaptureFixture[str]) -> None:
    """The argparse ``main`` entrypoint should accept the documented flags and print a summary."""
    run_results_path, manifest_path, warehouse_path = artifacts
    publisher = _load_publisher()
    rc = publisher.main(  # type: ignore[attr-defined]
        [
            "--run-results",
            str(run_results_path),
            "--manifest",
            str(manifest_path),
            "--warehouse",
            str(warehouse_path),
        ],
    )
    assert rc == 0
    captured = capsys.readouterr()
    assert "wrote 3 rows" in captured.out
