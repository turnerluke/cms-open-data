"""Generated bulk-CSV extraction assets.

The provider-summary-by-type-of-service datasets — Medicare Physician &
Other Practitioners, Part D Prescribers, Inpatient/Outpatient Hospitals
— are tens of millions of rows wide. Pulling them through the DKAN
datastore-pagination path (one JSON GET per 1,000 rows) is impractical:
the Physician-by-Provider-and-Service file alone is ~10M rows.

This module sidesteps that. Each ``dkan_data_api_bulk`` row in
``datasets.toml`` becomes an asset that resolves the dataset's annual
CSV ``downloadURL``, downloads it to a temp file next to the asset's
staging directory, then hands the local path to DuckDB
(``read_csv`` + ``write_parquet``).

Why download first instead of streaming through DuckDB httpfs: some CMS
CSVs (notably the 8.4 GB Open Payments general-payments file on
``download.cms.gov``, served by Akamai NetStorage) come back with no
``Content-Length`` and no ``Accept-Ranges`` header, so DuckDB httpfs
cannot do range reads and buffers the entire body — GitHub Actions
runners OOM and the job dies. Streaming the download in chunks over
``httpx`` keeps memory flat regardless of file size; the local convert
is then a plain vectorized DuckDB scan.

We bypass the Parquet IO manager because returning a ``pyarrow.Table``
would defeat the streaming win — but we reuse its on-disk layout and
publish helpers (stage to a temp name, atomically promote to
``<root>/<asset_name>/data.parquet``) so dbt's existing
``external_location`` glob sees exactly one live file per asset.
"""

from collections.abc import Callable
from pathlib import Path
import uuid

from cms_api import (
    MEDICAID_BASE_URL,
    OPEN_PAYMENTS_BASE_URL,
    DatasetSpec,
    get_data_api_csv_url,
    get_dkan_dataset_csv_url,
    load_registry,
)
import duckdb
import httpx

from cms_pipelines.defs.cms.vintage_sidecar import capture_dataset_vintage
from cms_pipelines.defs.io_managers.parquet import publish_parquet, staged_write
from cms_pipelines.defs.resources import resolve_raw_root
from dagster import AssetExecutionContext, AssetsDefinition, MaterializeResult, MetadataValue, asset


_ASSET_PREFIX = "cms_"

# 512 KiB per chunk keeps download throughput close to line rate without
# pinning much memory; the multi-GB CMS files spend seconds to minutes
# in this loop and never hold more than one chunk at a time.
_DOWNLOAD_CHUNK_BYTES = 512 * 1024

# Generous read timeout: the biggest CMS bulk CSVs are multi-GB served
# from download.cms.gov and can idle briefly between chunks on slower
# runners. The default 5s read timeout is way too aggressive.
_DOWNLOAD_TIMEOUT = httpx.Timeout(30.0, read=600.0)


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


def _stream_download(*, csv_url: str, dest: Path) -> None:
    """Stream ``csv_url`` to ``dest`` in fixed-size chunks over HTTPS.

    Chunks are written straight to disk so the response body is never
    materialized in Python memory — required because CMS bulk files
    range from hundreds of MB to ~8 GB. Redirects are followed because
    ``download.cms.gov`` sometimes 302s through Akamai.
    """
    with (
        dest.open("wb") as fh,
        httpx.stream(
            "GET",
            csv_url,
            follow_redirects=True,
            timeout=_DOWNLOAD_TIMEOUT,
        ) as response,
    ):
        response.raise_for_status()
        for chunk in response.iter_bytes(chunk_size=_DOWNLOAD_CHUNK_BYTES):
            fh.write(chunk)


def _run_bulk_load(*, csv_url: str, out_path: Path) -> int:
    """Download ``csv_url`` to a local temp file, then convert to Parquet.

    Uses DuckDB's Python relation API (``read_csv`` + ``write_parquet``)
    rather than ``COPY ... TO ?`` — the latter rejects parameter binding
    for its destination path. The CSV is downloaded first (see module
    docstring for why we don't hand the URL to DuckDB httpfs) into a
    hidden sibling of ``out_path`` and removed in a ``finally`` block
    so a failed convert never leaks a large temp file.

    ``sample_size=-1`` forces DuckDB to scan the entire CSV during type
    sniffing. The default 20 000-row sample misdetects columns whose
    type flips deep in a multi-GB file — the Open Payments general file
    has ~150 000 numeric US ZIPs before the first alphanumeric UK
    postcode, which makes the default sniff pick ``BIGINT`` and then
    fail mid-conversion. A full-file sniff is cheap now that the CSV is
    local. The row-count is read back from the landed Parquet so a
    header-only CSV trips the same guard as a zero-byte CSV would.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    local_csv = out_path.parent / f".{uuid.uuid4().hex}.csv.download"
    try:
        _stream_download(csv_url=csv_url, dest=local_csv)
        with duckdb.connect(":memory:") as con:
            relation = con.read_csv(str(local_csv), header=True, sample_size=-1)
            relation.write_parquet(str(out_path))
            row = con.execute("SELECT COUNT(*) FROM read_parquet(?)", [str(out_path)]).fetchone()
    finally:
        local_csv.unlink(missing_ok=True)
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
        csv_url = resolve(spec)
        context.log.info("Bulk-loading %s from %s", asset_name, csv_url)
        with staged_write(Path(resolve_raw_root()) / asset_name, context.run.run_id) as staged:
            row_count = _run_bulk_load(csv_url=csv_url, out_path=staged)
            if row_count == 0:
                msg = f"{asset_name} produced zero rows; refusing to land empty Parquet"
                raise RuntimeError(msg)
            out_path = publish_parquet(staged)
        vintage_path = capture_dataset_vintage(spec, raw_root=Path(resolve_raw_root()), asset_name=asset_name)
        return MaterializeResult(
            metadata={
                "path": MetadataValue.path(str(out_path)),
                "row_count": MetadataValue.int(row_count),
                "csv_url": MetadataValue.url(csv_url),
                "vintage_path": MetadataValue.path(str(vintage_path)),
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
