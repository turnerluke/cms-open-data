"""Tests for vintage sidecar persistence and the backfill CLI.

Upstream metadata fetches are stubbed by the autouse conftest fixture
(`_isolated_vintage_capture`), so everything here runs offline and
against ``tmp_path``.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import TYPE_CHECKING

from cms_api import DatasetSpec, DatasetVintage, load_registry, local_vintage
from cms_pipelines import vintage_backfill
from cms_pipelines.defs.cms import registry_assets
from cms_pipelines.defs.cms.vintage_sidecar import VINTAGES_DIRNAME, capture_dataset_vintage, write_vintage_sidecar
from cms_pipelines.defs.io_managers.parquet import ParquetIOManager
import pyarrow.parquet as pq

from dagster import materialize


if TYPE_CHECKING:
    from pathlib import Path

    import pytest


def _full_vintage(dataset_key: str = "hospital_general_information") -> DatasetVintage:
    """Build a vintage with every upstream date populated."""
    return DatasetVintage(
        dataset_key=dataset_key,
        source_family="dkan_provider_data",
        dataset_id="xubh-q36u",
        modified=date(2026, 7, 22),
        issued=date(2025, 1, 8),
        released=date(2026, 8, 13),
        temporal_start=None,
        temporal_end=None,
        captured_at=datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC),
    )


def test_write_vintage_sidecar_lands_one_typed_row(tmp_path: Path) -> None:
    """The sidecar is a single-row Parquet with dates typed as dates."""
    target = write_vintage_sidecar(tmp_path, "cms_hospital_general_information", _full_vintage())

    assert target == tmp_path / VINTAGES_DIRNAME / "cms_hospital_general_information.parquet"
    table = pq.read_table(target)
    assert table.num_rows == 1
    row = table.to_pylist()[0]
    assert row["dataset_key"] == "hospital_general_information"
    assert row["modified"] == date(2026, 7, 22)
    assert row["released"] == date(2026, 8, 13)
    assert row["temporal_start"] is None
    assert row["captured_at"] is not None


def test_write_vintage_sidecar_null_dates_stay_date_typed(tmp_path: Path) -> None:
    """All-null upstream dates still land as DATE columns (stable dbt schema)."""
    target = write_vintage_sidecar(tmp_path, "cms_nppes_providers", local_vintage("nppes_providers", "nppes"))

    schema = pq.read_schema(target)
    assert str(schema.field("modified").type) == "date32[day]"
    assert str(schema.field("dataset_id").type) == "string"


def test_write_vintage_sidecar_replaces_previous_file(tmp_path: Path) -> None:
    """Re-writing a sidecar leaves exactly one live file with the new content."""
    write_vintage_sidecar(tmp_path, "cms_x", _full_vintage("first"))
    write_vintage_sidecar(tmp_path, "cms_x", _full_vintage("second"))

    files = list((tmp_path / VINTAGES_DIRNAME).glob("*.parquet"))
    assert len(files) == 1
    assert pq.read_table(files[0]).to_pylist()[0]["dataset_key"] == "second"


def test_capture_dataset_vintage_writes_spec_identity(tmp_path: Path) -> None:
    """`capture_dataset_vintage` persists the (stubbed) fetched vintage for the spec."""
    spec = next(s for s in load_registry() if s.source == "dkan_provider_data")

    target = capture_dataset_vintage(spec, raw_root=tmp_path, asset_name=f"cms_{spec.key}")

    row = pq.read_table(target).to_pylist()[0]
    assert row["dataset_key"] == spec.key
    assert row["source_family"] == "dkan_provider_data"
    assert row["dataset_id"] == spec.dataset_id


def test_registry_asset_materialization_writes_sidecar(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Materializing a registry asset lands the vintage sidecar next to the data.

    ``CMS_RAW_ROOT`` is pinned to this test's ``tmp_path`` (the autouse
    fixture already isolates it, but re-pinning keeps the assertion
    self-contained).
    """
    monkeypatch.setenv("CMS_RAW_ROOT", str(tmp_path))
    monkeypatch.setattr(
        registry_assets,
        "iter_provider_data_catalog",
        lambda _dataset_id: iter([{"facility_id": "010001"}]),
    )
    spec = next(s for s in load_registry() if s.source == "dkan_provider_data")
    asset_def = getattr(registry_assets, f"cms_{spec.key}")

    result = materialize([asset_def], resources={"parquet_io_manager": ParquetIOManager(root=str(tmp_path))})

    assert result.success
    sidecar = tmp_path / VINTAGES_DIRNAME / f"cms_{spec.key}.parquet"
    assert sidecar.exists()
    assert pq.read_table(sidecar).to_pylist()[0]["dataset_key"] == spec.key


def _seed_extract(raw_root: Path, asset_name: str) -> None:
    """Land a minimal fake extract so the backfill sees the dataset as present."""
    asset_dir = raw_root / asset_name
    asset_dir.mkdir(parents=True)
    (asset_dir / "data.parquet").write_bytes(b"not really parquet")


def test_backfill_writes_sidecars_only_for_extracted_datasets(tmp_path: Path) -> None:
    """Datasets without landed Parquet are skipped; NPPES gets a local vintage."""
    specs = load_registry()
    extracted, skipped = specs[0], specs[1]
    _seed_extract(tmp_path, f"cms_{extracted.key}")
    _seed_extract(tmp_path, "cms_nppes_providers")

    written = vintage_backfill.backfill_vintage_sidecars(tmp_path)

    assert written == [f"cms_{extracted.key}", "cms_nppes_providers"]
    vintages_dir = tmp_path / VINTAGES_DIRNAME
    assert (vintages_dir / f"cms_{extracted.key}.parquet").exists()
    assert not (vintages_dir / f"cms_{skipped.key}.parquet").exists()
    nppes_row = pq.read_table(vintages_dir / "cms_nppes_providers.parquet").to_pylist()[0]
    assert nppes_row["source_family"] == "nppes"
    assert nppes_row["modified"] is None


def test_backfill_main_reports_written_assets(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The CLI prints each written asset and a summary count."""
    spec: DatasetSpec = load_registry()[0]
    _seed_extract(tmp_path, f"cms_{spec.key}")

    exit_code = vintage_backfill.main(["--raw-root", str(tmp_path)])

    assert exit_code == 0
    out = capsys.readouterr().out
    assert f"cms_{spec.key}" in out
    assert "backfilled 1 vintage sidecar(s)" in out
