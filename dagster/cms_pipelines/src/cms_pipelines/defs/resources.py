"""Shared Dagster resource registration.

Single registry for cross-cutting resources used across asset groups.
Per-source modules (``defs/cms/`` etc.) reference resources by key here.
"""

import os
from pathlib import Path

from .io_managers.parquet import ParquetIOManager

from dagster import Definitions, definitions


# Path layout: this file lives at
#   <repo>/dagster/cms_pipelines/src/cms_pipelines/defs/resources.py
# The repository root is therefore four parents up.
_REPO_ROOT = Path(__file__).resolve().parents[4]
_DEFAULT_RAW_ROOT = _REPO_ROOT / "data" / "raw"

CMS_RAW_ROOT_ENV = "CMS_RAW_ROOT"


def resolve_raw_root() -> str:
    """Resolve the raw-data root from the env var, falling back to ``data/raw/``.

    Shared by the Parquet IO manager and by assets that write Parquet
    directly (e.g. the DuckDB bulk-CSV loader), so both populate the same
    on-disk layout dbt's ``external_location`` already targets.
    """
    return os.environ.get(CMS_RAW_ROOT_ENV, str(_DEFAULT_RAW_ROOT))


@definitions
def shared_resources() -> Definitions:
    """Register the shared Parquet IO manager.

    The IO manager itself is layer- and source-neutral; the root is configured
    to point at the raw-extraction landing zone (``data/raw/``) because that's
    where the only consumers currently write. Add a second instance with a
    different root when another lakehouse layer needs the same IO manager.
    """
    return Definitions(
        resources={
            "parquet_io_manager": ParquetIOManager(root=resolve_raw_root()),
        },
    )
