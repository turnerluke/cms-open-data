"""Vintage sidecar persistence for raw extracts.

Each extraction asset lands its data as ``<root>/<asset_name>/*.parquet``
and — via :func:`capture_dataset_vintage` — a one-row Parquet *sidecar*
at ``<root>/_vintages/<asset_name>.parquet`` recording which upstream
snapshot the extract came from (see :mod:`cms_api.vintage`).

Sidecars live in a dedicated ``_vintages/`` directory rather than next to
the data file because dbt's ``external_location`` glob for each dataset
is ``<asset_name>/*.parquet`` — a sidecar inside the asset directory
would be unioned into the dataset itself. The ``_vintages/*.parquet``
glob instead feeds a single consolidated dbt source table
(``cms_vintages.dataset_vintages``), one row per extracted dataset.

Writes use the same stage-then-rename pattern as the Parquet IO manager
so a failed write never clobbers the previous good sidecar.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from cms_api import fetch_dataset_vintage
import pyarrow as pa
import pyarrow.parquet as pq


if TYPE_CHECKING:
    from pathlib import Path

    from cms_api import DatasetSpec, DatasetVintage


VINTAGES_DIRNAME = "_vintages"

# Explicit schema so all-null date columns (e.g. a healthcare.gov extract
# with no upstream metadata) still land typed as DATE, keeping the dbt
# source's unioned schema stable across sidecars.
_VINTAGE_SCHEMA = pa.schema(
    [
        ("dataset_key", pa.string()),
        ("source_family", pa.string()),
        ("dataset_id", pa.string()),
        ("modified", pa.date32()),
        ("issued", pa.date32()),
        ("released", pa.date32()),
        ("temporal_start", pa.date32()),
        ("temporal_end", pa.date32()),
        ("captured_at", pa.timestamp("us", tz="UTC")),
    ],
)


def write_vintage_sidecar(raw_root: Path, asset_name: str, vintage: DatasetVintage) -> Path:
    """Write ``vintage`` as the one-row sidecar for ``asset_name``.

    Returns the sidecar path (``<raw_root>/_vintages/<asset_name>.parquet``).
    The write is staged to a dot-prefixed temp name (invisible to the
    ``*.parquet`` glob) and atomically renamed into place.
    """
    out_dir = raw_root / VINTAGES_DIRNAME
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{asset_name}.parquet"
    staged = out_dir / f".{asset_name}.parquet.tmp"
    table = pa.Table.from_pylist([vintage.model_dump()], schema=_VINTAGE_SCHEMA)
    try:
        pq.write_table(table, staged)
    except BaseException:
        staged.unlink(missing_ok=True)
        raise
    staged.replace(target)
    return target


def capture_dataset_vintage(spec: DatasetSpec, *, raw_root: Path, asset_name: str) -> Path:
    """Fetch ``spec``'s current upstream vintage and persist its sidecar.

    Called by every registry-driven extraction asset right after the
    extract itself succeeds, so the sidecar always describes the snapshot
    that was just landed. Fetch failures propagate and fail the
    materialization — stale vintage metadata next to fresh data would be
    worse than a loud retry.
    """
    return write_vintage_sidecar(raw_root, asset_name, fetch_dataset_vintage(spec))
