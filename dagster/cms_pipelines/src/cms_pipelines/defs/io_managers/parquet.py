"""Parquet IO manager.

Writes ``pyarrow.Table`` outputs to ``<root>/<asset_name>/data.parquet``
and reads them back. The asset name is the last component of
``context.asset_key.path``; each materialization replaces the previous
one, so the directory always holds exactly one live Parquet file — the
latest run wins. That keeps DuckDB's ``external_location`` glob
(``<asset_name>/*.parquet``) free of duplicate rows across re-runs.

Writes are staged to a run-scoped temp name (which the ``*.parquet``
glob does not match) and atomically renamed into place, so a failed or
interrupted write never clobbers the previous good file — and the
staged file itself is unlinked on failure, so failed runs leave no
``.tmp`` files behind.

The class is layer- and source-neutral: callers pick the on-disk root
when they register the resource. The module-level helpers
(:func:`staged_write` / :func:`publish_parquet`) are shared with asset
modules that stream Parquet to disk directly (e.g. via DuckDB) but must
uphold the same one-live-file invariant.
"""

from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from typing import TYPE_CHECKING

import pyarrow as pa
import pyarrow.parquet as pq

from dagster import ConfigurableIOManager, InputContext, OutputContext


if TYPE_CHECKING:
    from collections.abc import Iterator


DATA_FILENAME = "data.parquet"


def staging_path(asset_dir: Path, run_id: str) -> Path:
    """Return a run-scoped temp path in ``asset_dir`` invisible to ``*.parquet`` globs."""
    return asset_dir / f".{run_id}.parquet.tmp"


@contextmanager
def staged_write(asset_dir: Path, run_id: str) -> Iterator[Path]:
    """Yield a run-scoped staging path in ``asset_dir``, discarding it on failure.

    Creates ``asset_dir`` if needed. If the body raises before
    :func:`publish_parquet` promotes the staged file, the staged file is
    unlinked so a failed write never leaks a ``.tmp`` file (nothing else
    prunes staged names — a blanket prune would race a concurrent run's
    in-flight staging). The exception propagates and the previous live
    ``data.parquet``, if any, is left untouched.
    """
    asset_dir.mkdir(parents=True, exist_ok=True)
    staged = staging_path(asset_dir, run_id)
    try:
        yield staged
    except BaseException:
        staged.unlink(missing_ok=True)
        raise


def publish_parquet(staged: Path) -> Path:
    """Atomically promote ``staged`` to the live ``data.parquet`` in its directory.

    After the rename, any other ``*.parquet`` files in the directory
    (e.g. per-run files landed before writes became idempotent) are
    pruned so exactly one live file remains.
    """
    asset_dir = staged.parent
    target = asset_dir / DATA_FILENAME
    staged.replace(target)
    for stale in asset_dir.glob("*.parquet"):
        if stale != target:
            # missing_ok: a concurrent run may have pruned the same legacy
            # file already; losing that race must not fail this publish.
            stale.unlink(missing_ok=True)
    return target


class ParquetIOManager(ConfigurableIOManager):
    """Writes ``pyarrow.Table`` asset outputs to ``<root>/<asset>/data.parquet``."""

    root: str

    def _asset_dir(self, context: OutputContext | InputContext) -> Path:
        return Path(self.root) / context.asset_key.path[-1]

    def handle_output(self, context: OutputContext, obj: object) -> None:
        """Write ``obj`` as the asset's single live Parquet file and emit metadata."""
        if not isinstance(obj, pa.Table):
            msg = f"ParquetIOManager only handles pyarrow.Table; got {type(obj).__name__}"
            raise TypeError(msg)
        with staged_write(self._asset_dir(context), context.run_id) as staged:
            pq.write_table(obj, staged)
            target = publish_parquet(staged)
        context.add_output_metadata(
            {
                "path": str(target),
                "row_count": obj.num_rows,
                "column_count": obj.num_columns,
            },
        )

    def load_input(self, context: InputContext) -> pa.Table:
        """Read the asset's live Parquet file.

        Useful for downstream Dagster assets that want the latest landed
        data; dbt reads the same directory in place via
        ``external_location``.
        """
        target = self._asset_dir(context) / DATA_FILENAME
        if not target.exists():
            msg = f"No parquet file found at {target}"
            raise FileNotFoundError(msg)
        return pq.read_table(target)
