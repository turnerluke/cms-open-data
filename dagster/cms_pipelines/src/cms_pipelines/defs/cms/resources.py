"""Resource registration for the CMS extraction layer.

Wires the ``cms_raw_io_manager`` resource that every ``cms`` asset writes
through. The on-disk root is the repository's ``data/raw/`` directory by
default; override with the ``CMS_RAW_ROOT`` environment variable for tests
or alternate deployments.
"""

from __future__ import annotations

import os
from pathlib import Path

from .io_manager import RawParquetIOManager

from dagster import Definitions, definitions


# Path layout: cms_pipelines is installed at
#   <repo>/dagster/cms_pipelines/src/cms_pipelines/defs/cms/resources.py
# The repository root is therefore five parents up.
_REPO_ROOT = Path(__file__).resolve().parents[5]
_DEFAULT_RAW_ROOT = _REPO_ROOT / "data" / "raw"

CMS_RAW_ROOT_ENV = "CMS_RAW_ROOT"


def _resolve_raw_root() -> str:
    """Resolve the raw-data root from the env var, falling back to ``data/raw/``."""
    return os.environ.get(CMS_RAW_ROOT_ENV, str(_DEFAULT_RAW_ROOT))


@definitions
def cms_resources() -> Definitions:
    """Register the shared raw-Parquet IO manager for every ``cms`` asset."""
    return Definitions(
        resources={
            "cms_raw_io_manager": RawParquetIOManager(root=_resolve_raw_root()),
        },
    )
