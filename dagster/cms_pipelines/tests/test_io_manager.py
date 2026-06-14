"""Unit tests for :class:`RawParquetIOManager`."""

from pathlib import Path

from cms_pipelines.defs.cms.io_manager import RawParquetIOManager
import pyarrow as pa
import pyarrow.parquet as pq

from dagster import AssetKey, build_input_context, build_output_context

import pytest


def _two_row_table() -> pa.Table:
    """Build a tiny pyarrow Table fixture used across these tests."""
    return pa.Table.from_pylist([{"a": 1, "b": "x"}, {"a": 2, "b": "y"}])


def test_handle_output_writes_parquet_under_asset_dir(tmp_path: Path) -> None:
    """Outputs land at `<root>/<asset_name>/<run_id>.parquet`."""
    io_manager = RawParquetIOManager(root=str(tmp_path))
    ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")

    io_manager.handle_output(ctx, _two_row_table())

    target = tmp_path / "cms_demo" / "run-1.parquet"
    assert target.exists()
    assert pq.read_table(target).num_rows == 2


def test_handle_output_rejects_non_table(tmp_path: Path) -> None:
    """Anything other than a pyarrow.Table is rejected loudly."""
    io_manager = RawParquetIOManager(root=str(tmp_path))
    ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")

    with pytest.raises(TypeError, match=r"only handles pyarrow\.Table"):
        io_manager.handle_output(ctx, {"not": "a table"})


def test_load_input_reads_back_what_handle_output_wrote(tmp_path: Path) -> None:
    """A write followed by a read returns the original rows and columns."""
    io_manager = RawParquetIOManager(root=str(tmp_path))
    out_ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")
    in_ctx = build_input_context(asset_key=AssetKey("cms_demo"))

    io_manager.handle_output(out_ctx, _two_row_table())
    result = io_manager.load_input(in_ctx)

    assert result.num_rows == 2
    assert set(result.column_names) == {"a", "b"}


def test_load_input_raises_when_directory_empty(tmp_path: Path) -> None:
    """Reading an asset with no landed Parquet is a hard error, not a silent empty."""
    io_manager = RawParquetIOManager(root=str(tmp_path))
    in_ctx = build_input_context(asset_key=AssetKey("cms_demo"))

    with pytest.raises(FileNotFoundError):
        io_manager.load_input(in_ctx)


def test_handle_output_creates_parent_dir_if_missing(tmp_path: Path) -> None:
    """Asset dir is created lazily, not pre-allocated."""
    nested = tmp_path / "nested" / "raw"
    assert not nested.exists()

    io_manager = RawParquetIOManager(root=str(nested))
    ctx = build_output_context(asset_key=AssetKey("cms_demo"), run_id="run-1")
    io_manager.handle_output(ctx, _two_row_table())

    assert (nested / "cms_demo" / "run-1.parquet").exists()
