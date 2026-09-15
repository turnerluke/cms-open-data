"""Tests for the durable vintage ledger CLI.

Synthetic sidecar + data Parquet trees under ``tmp_path`` — the CLI
never touches the network, so no fixtures need stubbing beyond the
autouse ``_isolated_vintage_capture`` in ``conftest.py``.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
import json
from typing import TYPE_CHECKING

from cms_api import DatasetVintage
from cms_pipelines import vintage_ledger
from cms_pipelines.defs.cms.vintage_sidecar import write_vintage_sidecar
import pyarrow as pa
import pyarrow.parquet as pq

import pytest


if TYPE_CHECKING:
    from pathlib import Path


def _make_vintage(
    dataset_key: str,
    *,
    captured_at: datetime,
    modified: date | None = date(2026, 7, 22),
    source_family: str = "dkan_provider_data",
) -> DatasetVintage:
    """Build a sidecar-shaped vintage for tests."""
    return DatasetVintage(
        dataset_key=dataset_key,
        source_family=source_family,
        dataset_id="xubh-q36u",
        modified=modified,
        issued=date(2025, 1, 8),
        released=date(2026, 8, 13),
        temporal_start=None,
        temporal_end=None,
        captured_at=captured_at,
    )


def _write_data_parquet(raw_root: Path, asset_name: str, table: pa.Table, filename: str = "data.parquet") -> None:
    """Land a real Parquet under the asset's data directory."""
    asset_dir = raw_root / asset_name
    asset_dir.mkdir(parents=True, exist_ok=True)
    pq.write_table(table, asset_dir / filename)


def _seed_dataset(
    raw_root: Path,
    dataset_key: str,
    *,
    captured_at: datetime,
    table: pa.Table,
    modified: date | None = date(2026, 7, 22),
) -> str:
    """Write a sidecar + data parquet for one dataset; return the asset name."""
    asset_name = f"cms_{dataset_key}"
    write_vintage_sidecar(raw_root, asset_name, _make_vintage(dataset_key, captured_at=captured_at, modified=modified))
    _write_data_parquet(raw_root, asset_name, table)
    return asset_name


def _read_ledger_rows(path: Path) -> list[dict[str, object]]:
    """Load the JSONL ledger as a list of dicts."""
    with path.open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def test_append_writes_one_row_per_sidecar(tmp_path: Path) -> None:
    """One JSONL row lands per sidecar with sidecar fields + Parquet-footer stats."""
    raw_root = tmp_path / "raw"
    ledger = tmp_path / "vintages" / "ledger.jsonl"
    _seed_dataset(
        raw_root,
        "hospital_general_information",
        captured_at=datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["010001", "010002"]}),
    )
    _seed_dataset(
        raw_root,
        "home_health_care_agencies",
        captured_at=datetime(2026, 9, 6, 12, 5, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["1", "2", "3"]}),
    )

    added, skipped = vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=ledger)

    assert (added, skipped) == (2, 0)
    rows = _read_ledger_rows(ledger)
    assert len(rows) == 2
    by_key = {r["dataset_key"]: r for r in rows}
    hgi = by_key["hospital_general_information"]
    assert hgi["run_date"] == "2026-09-06"
    assert hgi["row_count"] == 2
    assert hgi["file_count"] == 1
    assert hgi["asset_name"] == "cms_hospital_general_information"
    assert hgi["captured_at"] == "2026-09-06T12:00:00+00:00"
    assert hgi["modified"] == "2026-07-22"
    assert isinstance(hgi["schema_hash"], str)
    assert len(hgi["schema_hash"]) == 12


def test_append_dedupes_same_day_rerun(tmp_path: Path) -> None:
    """Re-running against the same sidecar is a no-op: dedupe on (run_date, key)."""
    raw_root = tmp_path / "raw"
    ledger = tmp_path / "ledger.jsonl"
    _seed_dataset(
        raw_root,
        "hospital_general_information",
        captured_at=datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["010001"]}),
    )
    vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=ledger)

    added, skipped = vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=ledger)

    assert added == 0
    assert skipped == 1
    assert len(_read_ledger_rows(ledger)) == 1


def test_merge_from_existing_wins_on_conflict(tmp_path: Path) -> None:
    """`--merge-from` carries forward unique keys but never overwrites existing."""
    raw_root = tmp_path / "raw"
    ledger = tmp_path / "ledger.jsonl"
    other = tmp_path / "other.jsonl"

    _seed_dataset(
        raw_root,
        "hospital_general_information",
        captured_at=datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["010001"]}),
    )
    vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=ledger)
    original_rows = _read_ledger_rows(ledger)

    # Conflicting row (same (run_date, dataset_key)) plus a unique row.
    conflict = dict(original_rows[0])
    conflict["row_count"] = 99999  # bogus — should be ignored by dedupe
    unique_row = dict(original_rows[0])
    unique_row["dataset_key"] = "other_dataset"
    unique_row["asset_name"] = "cms_other_dataset"
    with other.open("w", encoding="utf-8") as f:
        f.write(json.dumps(conflict) + "\n")
        f.write(json.dumps(unique_row) + "\n")

    added, _ = vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=ledger, merge_from=other)

    assert added == 1
    final = _read_ledger_rows(ledger)
    by_key = {(r["run_date"], r["dataset_key"]): r for r in final}
    # existing ledger row survived unchanged
    assert by_key[("2026-09-06", "hospital_general_information")]["row_count"] == 1
    # unique row from other was carried forward
    assert ("2026-09-06", "other_dataset") in by_key


def test_verify_superset_pass_and_fail(tmp_path: Path) -> None:
    """`verify_superset` returns [] when every reference key is covered, else missing."""
    a = tmp_path / "a.jsonl"
    b = tmp_path / "b.jsonl"
    rows_a = [
        {"run_date": "2026-09-06", "dataset_key": "x"},
        {"run_date": "2026-09-06", "dataset_key": "y"},
    ]
    rows_b = [{"run_date": "2026-09-06", "dataset_key": "x"}]
    a.write_text("\n".join(json.dumps(r) for r in rows_a) + "\n", encoding="utf-8")
    b.write_text("\n".join(json.dumps(r) for r in rows_b) + "\n", encoding="utf-8")

    assert vintage_ledger.verify_superset(ledger_path=a, reference_path=b) == []
    # b is not a superset of a — one key ("y") missing.
    missing = vintage_ledger.verify_superset(ledger_path=b, reference_path=a)
    assert missing == [("2026-09-06", "y")]


def test_schema_hash_stable_and_sensitive(tmp_path: Path) -> None:
    """Schema hash is stable across data changes and flips on a column rename."""
    raw_root = tmp_path / "raw"
    ledger = tmp_path / "ledger.jsonl"
    _seed_dataset(
        raw_root,
        "hospital_general_information",
        captured_at=datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["010001"], "name": ["A"]}),
    )
    vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=ledger)
    first_hash = _read_ledger_rows(ledger)[0]["schema_hash"]

    # Same schema, different data, next day -> same hash.
    ledger2 = tmp_path / "ledger2.jsonl"
    raw2 = tmp_path / "raw2"
    _seed_dataset(
        raw2,
        "hospital_general_information",
        captured_at=datetime(2026, 9, 7, 12, 0, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["010999"], "name": ["Z"]}),
    )
    vintage_ledger.append_ledger(raw_root=raw2, ledger_path=ledger2)
    assert _read_ledger_rows(ledger2)[0]["schema_hash"] == first_hash

    # Renamed column -> different hash.
    ledger3 = tmp_path / "ledger3.jsonl"
    raw3 = tmp_path / "raw3"
    _seed_dataset(
        raw3,
        "hospital_general_information",
        captured_at=datetime(2026, 9, 8, 12, 0, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["010001"], "hospital_name": ["A"]}),
    )
    vintage_ledger.append_ledger(raw_root=raw3, ledger_path=ledger3)
    assert _read_ledger_rows(ledger3)[0]["schema_hash"] != first_hash


def test_row_count_sums_across_multiple_files(tmp_path: Path) -> None:
    """`row_count` sums Parquet-footer `num_rows` across every `*.parquet` file."""
    raw_root = tmp_path / "raw"
    ledger = tmp_path / "ledger.jsonl"
    asset_name = _seed_dataset(
        raw_root,
        "hospital_general_information",
        captured_at=datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC),
        table=pa.table({"ccn": ["010001", "010002"]}),
    )
    _write_data_parquet(raw_root, asset_name, pa.table({"ccn": ["010003", "010004", "010005"]}), filename="part2.parquet")

    vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=ledger)
    row = _read_ledger_rows(ledger)[0]
    assert row["row_count"] == 5
    assert row["file_count"] == 2


def test_run_date_converts_offset_strings_to_utc() -> None:
    """An offset-bearing ISO string yields the UTC calendar date."""
    late_pacific = "2026-09-06T23:30:00-08:00"
    assert vintage_ledger._run_date_from_captured_at(late_pacific) == "2026-09-07"
    assert vintage_ledger._run_date_from_captured_at("2026-09-06T12:00:00+00:00") == "2026-09-06"


def test_append_fails_fast_when_data_missing(tmp_path: Path) -> None:
    """A sidecar without landed parquet raises instead of recording a 0-row row."""
    raw_root = tmp_path / "raw"
    write_vintage_sidecar(
        raw_root,
        "cms_hospital_general_information",
        _make_vintage("hospital_general_information", captured_at=datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC)),
    )

    with pytest.raises(FileNotFoundError, match="no parquet files"):
        vintage_ledger.append_ledger(raw_root=raw_root, ledger_path=tmp_path / "ledger.jsonl")


def test_read_ledger_rejects_newer_ledger_version(tmp_path: Path) -> None:
    """Rows from a newer ledger_version are refused, never silently truncated."""
    path = tmp_path / "ledger.jsonl"
    row = {"ledger_version": vintage_ledger.LEDGER_VERSION + 1, "run_date": "2026-09-06", "dataset_key": "x"}
    path.write_text(json.dumps(row) + "\n", encoding="utf-8")

    with pytest.raises(ValueError, match="ledger_version"):
        vintage_ledger.read_ledger(path)
