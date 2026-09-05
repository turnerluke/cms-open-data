"""Unit tests for :class:`ParquetIOManager` and its publish helpers."""

from pathlib import Path

from cms_pipelines.defs.io_managers.parquet import DATA_FILENAME, ParquetIOManager, publish_parquet, staged_write, staging_path
import pyarrow as pa
import pyarrow.parquet as pq

from dagster import AssetKey, build_input_context, build_output_context

import pytest


def _two_row_table() -> pa.Table:
    """Build a tiny pyarrow Table fixture used across these tests."""
    return pa.Table.from_pylist([{"a": 1, "b": "x"}, {"a": 2, "b": "y"}])


def test_handle_output_writes_parquet_under_asset_dir(tmp_path: Path) -> None:
    """Outputs land at `<root>/<asset_name>/data.parquet`."""
    io_manager = ParquetIOManager(root=str(tmp_path))
    ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")

    io_manager.handle_output(ctx, _two_row_table())

    target = tmp_path / "cms_demo" / DATA_FILENAME
    assert target.exists()
    assert pq.read_table(target).num_rows == 2


def test_handle_output_is_idempotent_across_runs(tmp_path: Path) -> None:
    """Two materializations leave exactly one file holding the second run's data."""
    io_manager = ParquetIOManager(root=str(tmp_path))
    first = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")
    second = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-2")

    io_manager.handle_output(first, _two_row_table())
    io_manager.handle_output(second, pa.Table.from_pylist([{"a": 3, "b": "z"}]))

    files = list((tmp_path / "cms_demo").glob("*.parquet"))
    assert files == [tmp_path / "cms_demo" / DATA_FILENAME]
    table = pq.read_table(files[0])
    assert table.num_rows == 1
    assert table.column("a").to_pylist() == [3]


def test_handle_output_prunes_legacy_per_run_files(tmp_path: Path) -> None:
    """Run-UUID files landed before the idempotency fix are removed on the next write."""
    asset_dir = tmp_path / "cms_demo"
    asset_dir.mkdir()
    pq.write_table(_two_row_table(), asset_dir / "old-run-uuid.parquet")

    io_manager = ParquetIOManager(root=str(tmp_path))
    ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-2")
    io_manager.handle_output(ctx, _two_row_table())

    assert sorted(asset_dir.glob("*.parquet")) == [asset_dir / DATA_FILENAME]


def test_handle_output_rejects_non_table(tmp_path: Path) -> None:
    """Anything other than a pyarrow.Table is rejected loudly."""
    io_manager = ParquetIOManager(root=str(tmp_path))
    ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")

    with pytest.raises(TypeError, match=r"only handles pyarrow\.Table"):
        io_manager.handle_output(ctx, {"not": "a table"})


def test_load_input_reads_back_what_handle_output_wrote(tmp_path: Path) -> None:
    """A write followed by a read returns the original rows and columns."""
    io_manager = ParquetIOManager(root=str(tmp_path))
    out_ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")
    in_ctx = build_input_context(asset_key=AssetKey("cms_demo"))

    io_manager.handle_output(out_ctx, _two_row_table())
    result = io_manager.load_input(in_ctx)

    assert result.num_rows == 2
    assert set(result.column_names) == {"a", "b"}


def test_load_input_raises_when_directory_empty(tmp_path: Path) -> None:
    """Reading an asset with no landed Parquet is a hard error, not a silent empty."""
    io_manager = ParquetIOManager(root=str(tmp_path))
    in_ctx = build_input_context(asset_key=AssetKey("cms_demo"))

    with pytest.raises(FileNotFoundError):
        io_manager.load_input(in_ctx)


def test_handle_output_creates_parent_dir_if_missing(tmp_path: Path) -> None:
    """Asset dir is created lazily, not pre-allocated."""
    nested = tmp_path / "nested" / "raw"
    assert not nested.exists()

    io_manager = ParquetIOManager(root=str(nested))
    ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")
    io_manager.handle_output(ctx, _two_row_table())

    assert (nested / "cms_demo" / DATA_FILENAME).exists()


def test_staging_path_is_invisible_to_parquet_glob(tmp_path: Path) -> None:
    """A staged (in-flight) file must never match the dbt `*.parquet` glob."""
    staged = staging_path(tmp_path, "run-1")
    staged.write_bytes(b"partial")

    assert list(tmp_path.glob("*.parquet")) == []


def test_staged_write_unlinks_staged_file_on_error(tmp_path: Path) -> None:
    """A body that raises leaves no staged `.tmp` file behind."""
    asset_dir = tmp_path / "cms_demo"

    def failing_write() -> None:
        with staged_write(asset_dir, "run-1") as staged:
            staged.write_bytes(b"partial")
            msg = "boom"
            raise RuntimeError(msg)

    with pytest.raises(RuntimeError, match="boom"):
        failing_write()

    assert list(asset_dir.iterdir()) == []


def test_handle_output_failure_leaves_no_tmp_and_preserves_previous(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A write that raises mid-way cleans up its staged file and keeps the old live file."""
    io_manager = ParquetIOManager(root=str(tmp_path))
    first = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")
    io_manager.handle_output(first, _two_row_table())

    def failing_write_table(_table: pa.Table, where: Path) -> None:
        Path(where).write_bytes(b"partial")  # simulate a partial write before the failure
        msg = "disk full"
        raise OSError(msg)

    monkeypatch.setattr(pq, "write_table", failing_write_table)
    second = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-2")
    with pytest.raises(OSError, match="disk full"):
        io_manager.handle_output(second, _two_row_table())

    asset_dir = tmp_path / "cms_demo"
    assert list(asset_dir.glob(".*.tmp")) == []
    assert pq.read_table(asset_dir / DATA_FILENAME).num_rows == 2


def test_publish_parquet_promotes_staged_file_and_prunes(tmp_path: Path) -> None:
    """`publish_parquet` renames the staged file and removes stale siblings."""
    pq.write_table(_two_row_table(), tmp_path / "stale-run.parquet")
    staged = staging_path(tmp_path, "run-2")
    pq.write_table(pa.Table.from_pylist([{"a": 9}]), staged)

    target = publish_parquet(staged)

    assert target == tmp_path / DATA_FILENAME
    assert not staged.exists()
    assert sorted(tmp_path.glob("*.parquet")) == [target]
    assert pq.read_table(target).column("a").to_pylist() == [9]
