"""Parquet IO manager.

Writes ``pyarrow.Table`` outputs to ``<root>/<asset_name>/<run_id>.parquet``
and reads them back as one concatenated table. The asset name is the last
component of ``context.asset_key.path``; the per-run filename means multiple
materializations of the same asset accumulate side-by-side, which matches
the directory-glob shape DuckDB's ``external_location`` expects.

The class is layer- and source-neutral: callers pick the on-disk root when
they register the resource.
"""

from __future__ import annotations

from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

from dagster import ConfigurableIOManager, InputContext, OutputContext


class ParquetIOManager(ConfigurableIOManager):
    """Writes ``pyarrow.Table`` asset outputs to ``<root>/<asset>/<run_id>.parquet``."""

    root: str

    def _asset_dir(self, context: OutputContext | InputContext) -> Path:
        return Path(self.root) / context.asset_key.path[-1]

    def handle_output(self, context: OutputContext, obj: object) -> None:
        """Write ``obj`` as a Parquet file and emit row-count + path metadata."""
        if not isinstance(obj, pa.Table):
            msg = f"ParquetIOManager only handles pyarrow.Table; got {type(obj).__name__}"
            raise TypeError(msg)
        asset_dir = self._asset_dir(context)
        asset_dir.mkdir(parents=True, exist_ok=True)
        target = asset_dir / f"{context.run_id}.parquet"
        pq.write_table(obj, target)
        context.add_output_metadata(
            {
                "path": str(target),
                "row_count": obj.num_rows,
                "column_count": obj.num_columns,
            },
        )

    def load_input(self, context: InputContext) -> pa.Table:
        """Read every Parquet file in the asset's directory and return one concatenated table.

        Useful for downstream Dagster assets that want the latest landed data;
        dbt reads the same directory in place via ``external_location``.
        """
        asset_dir = self._asset_dir(context)
        files = sorted(asset_dir.glob("*.parquet"))
        if not files:
            msg = f"No parquet files found under {asset_dir}"
            raise FileNotFoundError(msg)
        return pq.read_table(asset_dir)
