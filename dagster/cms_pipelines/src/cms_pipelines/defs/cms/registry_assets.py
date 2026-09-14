"""Generated extraction assets for the CMS dataset registry.

One Dagster `@asset` per row in `libs/cms_api/datasets.toml`. The factory
routes each spec to the right `cms_api` client based on `spec.source`
(Socrata's `iter_dataset`, healthcare.gov's `get_static_json`, or DKAN's
`iter_provider_data_catalog`), lands the rows as Parquet via the shared
``staged_write`` / ``publish_parquet`` helpers, and raises if the extract
is empty — same guardrails the previous hand-written assets had.

Sidecar sequencing mirrors ``bulk_csv_assets`` / ``qhp_zip_assets``:
each asset manages its own Parquet publish (rather than deferring to
the shared Parquet IO manager) so the vintage sidecar can be written
*after* the Parquet is durably in place. A failed publish therefore
leaves the previous sidecar untouched instead of stamping a fresh
sidecar over stale data.

To add a dataset, append a `[[dataset]]` row to `datasets.toml` and the
asset shows up here automatically; no new module needed.
"""

from collections.abc import Callable
from pathlib import Path

from cms_api import DatasetSpec, JsonObject, iter_dataset, iter_provider_data_catalog, load_registry
from cms_api.healthcare_gov import get_static_json
import pyarrow as pa
import pyarrow.parquet as pq

from cms_pipelines.defs.cms.vintage_sidecar import capture_dataset_vintage
from cms_pipelines.defs.io_managers.parquet import publish_parquet, staged_write
from cms_pipelines.defs.resources import resolve_raw_root
from dagster import AssetExecutionContext, AssetsDefinition, MaterializeResult, MetadataValue, asset


_ASSET_PREFIX = "cms_"


def _socrata_rows(spec: DatasetSpec) -> list[JsonObject]:
    """Pull every row of a Socrata dataset for `spec`."""
    # DatasetSpec's cross-validator guarantees this, but mypy can't see
    # through the post-init check — narrow defensively.
    if spec.dataset_id is None:
        msg = f"socrata dataset {spec.key!r} is missing `dataset_id`"
        raise RuntimeError(msg)
    return list(iter_dataset(spec.dataset_id, domain=spec.domain))


def _healthcare_gov_rows(spec: DatasetSpec) -> list[JsonObject]:
    """Pull every row of a healthcare.gov static-JSON dataset for `spec`."""
    if spec.path is None:
        msg = f"healthcare_gov dataset {spec.key!r} is missing `path`"
        raise RuntimeError(msg)
    return get_static_json(spec.path)


def _dkan_provider_data_rows(spec: DatasetSpec) -> list[JsonObject]:
    """Pull every row of a Provider Data Catalog dataset for `spec`."""
    if spec.dataset_id is None:
        msg = f"dkan_provider_data dataset {spec.key!r} is missing `dataset_id`"
        raise RuntimeError(msg)
    return list(iter_provider_data_catalog(spec.dataset_id))


_FETCHERS: dict[str, Callable[[DatasetSpec], list[JsonObject]]] = {
    "socrata": _socrata_rows,
    "healthcare_gov": _healthcare_gov_rows,
    "dkan_provider_data": _dkan_provider_data_rows,
}


def _build_asset(spec: DatasetSpec) -> AssetsDefinition:
    """Return a Dagster asset that materializes `spec` into Parquet."""
    fetch = _FETCHERS[spec.source]
    asset_name = f"{_ASSET_PREFIX}{spec.key}"

    @asset(
        name=asset_name,
        group_name=spec.group,
        compute_kind="python",
        description=spec.description,
    )
    def _generated(context: AssetExecutionContext) -> MaterializeResult:
        rows = fetch(spec)
        if not rows:
            msg = f"{asset_name} returned zero rows; refusing to land empty Parquet"
            raise RuntimeError(msg)
        context.log.info("Fetched %d rows for %s", len(rows), asset_name)
        raw_root = Path(resolve_raw_root())
        table = pa.Table.from_pylist(rows)
        with staged_write(raw_root / asset_name, context.run.run_id) as staged:
            pq.write_table(table, staged)
            out_path = publish_parquet(staged)
        vintage_path = capture_dataset_vintage(spec, raw_root=raw_root, asset_name=asset_name)
        context.log.info("Wrote vintage sidecar %s", vintage_path)
        return MaterializeResult(
            metadata={
                "path": MetadataValue.path(str(out_path)),
                "row_count": MetadataValue.int(table.num_rows),
                "column_count": MetadataValue.int(table.num_columns),
                "vintage_path": MetadataValue.path(str(vintage_path)),
            },
        )

    return _generated


# Bind each generated asset into the module globals so Dagster's
# `load_from_defs_folder` discovers them by attribute name. This is the
# same mechanism that picks up `@asset`-decorated module-level functions
# in the hand-written modules; the difference is the names are computed
# at import time from the registry.
#
# Sources without a fetcher in `_FETCHERS` (e.g. `dkan_data_api_bulk`,
# which is handled in `bulk_csv_assets.py`, or `custom`, which flags a
# hand-written asset like `cms_nppes_providers`) are intentionally
# skipped so we don't emit a duplicate auto-generated asset.
for _spec in load_registry():
    if _spec.source not in _FETCHERS:
        continue
    globals()[f"{_ASSET_PREFIX}{_spec.key}"] = _build_asset(_spec)
del _spec
