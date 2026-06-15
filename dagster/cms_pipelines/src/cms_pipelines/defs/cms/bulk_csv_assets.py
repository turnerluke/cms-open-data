"""Generated bulk-CSV extraction assets.

The provider-summary-by-type-of-service datasets — Medicare Physician &
Other Practitioners, Part D Prescribers, Inpatient/Outpatient Hospitals
— are tens of millions of rows wide. Pulling them through the DKAN
datastore-pagination path (one JSON GET per 1,000 rows) is impractical:
the Physician-by-Provider-and-Service file alone is ~10M rows.

This module sidesteps that. Each ``dkan_data_api_bulk`` row in
``datasets.toml`` becomes an asset that hands the dataset's annual CSV
``downloadURL`` straight to DuckDB's ``read_csv_auto`` and writes Parquet
via ``COPY ... TO ... (FORMAT PARQUET)``. The CSV is never materialized
in Python memory, just streamed through DuckDB's vectorized engine.

We bypass the Parquet IO manager because returning a ``pyarrow.Table``
would defeat the streaming win — but we reuse its on-disk layout
(``<root>/<asset_name>/<run_id>.parquet``) so dbt's existing
``external_location`` glob picks the files up unchanged.
"""

from collections.abc import Callable
from pathlib import Path

from cms_api import (
    MEDICAID_BASE_URL,
    OPEN_PAYMENTS_BASE_URL,
    DatasetSpec,
    get_data_api_csv_url,
    get_dkan_dataset_csv_url,
    load_registry,
)
import duckdb

from cms_pipelines.defs.resources import resolve_raw_root
from dagster import AssetExecutionContext, AssetsDefinition, MaterializeResult, MetadataValue, asset


_ASSET_PREFIX = "cms_"


def _resolve_data_api_csv_url(spec: DatasetSpec) -> str:
    """Look up the CSV download URL for a data.cms.gov DCAT dataset."""
    if spec.dataset_id is None:
        msg = f"dkan_data_api_bulk dataset {spec.key!r} is missing `dataset_id`"
        raise RuntimeError(msg)
    return get_data_api_csv_url(spec.dataset_id, year=spec.year)


def _resolve_medicaid_csv_url(spec: DatasetSpec) -> str:
    """Look up the CSV download URL for a data.medicaid.gov DKAN dataset."""
    if spec.dataset_id is None:
        msg = f"dkan_medicaid_bulk dataset {spec.key!r} is missing `dataset_id`"
        raise RuntimeError(msg)
    return get_dkan_dataset_csv_url(spec.dataset_id, base_url=MEDICAID_BASE_URL)


def _resolve_open_payments_csv_url(spec: DatasetSpec) -> str:
    """Look up the CSV download URL for an openpaymentsdata.cms.gov dataset."""
    if spec.dataset_id is None:
        msg = f"dkan_open_payments_bulk dataset {spec.key!r} is missing `dataset_id`"
        raise RuntimeError(msg)
    return get_dkan_dataset_csv_url(spec.dataset_id, base_url=OPEN_PAYMENTS_BASE_URL)


_RESOLVERS: dict[str, Callable[[DatasetSpec], str]] = {
    "dkan_data_api_bulk": _resolve_data_api_csv_url,
    "dkan_medicaid_bulk": _resolve_medicaid_csv_url,
    "dkan_open_payments_bulk": _resolve_open_payments_csv_url,
}


def _run_bulk_load(*, csv_url: str, out_path: Path) -> int:
    """Stream ``csv_url`` to ``out_path`` via DuckDB; return rows written.

    Uses DuckDB's Python relation API (``read_csv`` + ``write_parquet``)
    rather than ``COPY ... TO ?`` — the latter rejects parameter binding
    for its destination path. ``read_csv`` accepts HTTPS URLs directly
    (DuckDB has built-in httpfs), so the CMS CSVs stream through without
    ever materializing in Python memory. The row-count is read back from
    the landed Parquet so a header-only CSV trips the same guard as a
    zero-byte CSV would.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(":memory:") as con:
        relation = con.read_csv(csv_url, header=True)
        relation.write_parquet(str(out_path))
        row = con.execute("SELECT COUNT(*) FROM read_parquet(?)", [str(out_path)]).fetchone()
    if row is None:
        msg = f"DuckDB returned no count row for {out_path}"
        raise RuntimeError(msg)
    return int(row[0])


def _build_asset(spec: DatasetSpec) -> AssetsDefinition:
    """Return a Dagster asset that streams ``spec``'s CSV into Parquet via DuckDB."""
    asset_name = f"{_ASSET_PREFIX}{spec.key}"
    resolve = _RESOLVERS[spec.source]

    @asset(
        name=asset_name,
        group_name=spec.group,
        compute_kind="duckdb",
        description=spec.description,
    )
    def _generated(context: AssetExecutionContext) -> MaterializeResult:
        out_path = Path(resolve_raw_root()) / asset_name / f"{context.run.run_id}.parquet"
        csv_url = resolve(spec)
        context.log.info("Bulk-loading %s from %s", asset_name, csv_url)
        row_count = _run_bulk_load(csv_url=csv_url, out_path=out_path)
        if row_count == 0:
            # Don't leave an empty Parquet behind — dbt's external_location
            # glob would happily pick it up.
            out_path.unlink(missing_ok=True)
            msg = f"{asset_name} produced zero rows; refusing to land empty Parquet"
            raise RuntimeError(msg)
        return MaterializeResult(
            metadata={
                "path": MetadataValue.path(str(out_path)),
                "row_count": MetadataValue.int(row_count),
                "csv_url": MetadataValue.url(csv_url),
            },
        )

    return _generated


# Bind one module-level attribute per bulk-CSV registry row so Dagster's
# `load_from_defs_folder` discovers them by name, the same way the
# JSON-paginated `registry_assets.py` factory works. Both
# `dkan_data_api_bulk` (data.cms.gov DCAT catalog) and `dkan_medicaid_bulk`
# (data.medicaid.gov metastore) land here — `_RESOLVERS` decides which
# client resolves the CSV URL.
for _spec in load_registry():
    if _spec.source not in _RESOLVERS:
        continue
    globals()[f"{_ASSET_PREFIX}{_spec.key}"] = _build_asset(_spec)
del _spec
