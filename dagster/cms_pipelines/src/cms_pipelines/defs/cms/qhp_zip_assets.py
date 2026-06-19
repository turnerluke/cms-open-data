"""Generated ZIP-XLSX extraction assets for QHP Landscape PUFs.

The QHP (Qualified Health Plan) Landscape Public Use Files at
``data.healthcare.gov`` are the bulk plan-landscape data behind the
healthcare.gov marketplace. Each plan year exposes four files:
Individual Medical, Individual Dental, SHOP Medical, SHOP Dental. Unlike
the DKAN datasets at ``data.medicaid.gov`` / ``openpaymentsdata.cms.gov``
— which distribute as direct CSV — CMS packages each QHP file as a
single ``.xlsx`` inside a ``.zip`` distribution. The consumer-facing
Marketplace API at ``marketplace.api.healthcare.gov`` exists to power
plan-shopping flows (per-household pricing) and isn't bulk-extractable,
so the PUFs are the canonical path to landscape data.

# Why a peer module instead of extending ``bulk_csv_assets``?

The CSV bulk path is a one-liner against DuckDB's HTTPFS — ``read_csv``
reads the URL directly with no on-disk staging. The ZIP-XLSX path
requires a temp dir (download ZIP, extract XLSX, hand the path to
DuckDB's ``read_xlsx``), and the XLSX itself has a non-standard layout:
row 1 holds a ``"N displayed records"`` count message, row 2 is the
header, data starts at row 3. Folding all of that into the CSV factory
would make it harder to read — separate concerns stay separate.

# Layout quirk: ``A2`` start with ``stop_at_empty``

DuckDB's ``read_xlsx`` accepts a ``range`` arg with a fixed upper bound;
combined with ``stop_at_empty=true`` it ignores trailing empty rows in
the range, which lets us use a single ``A2:ZZ1048576`` range across all
four files (none exceed Excel's 1,048,576-row per-sheet limit). ``A2:``
shape (open-ended start) is *not* supported, so the upper bound is load-
bearing. ``all_varchar=true`` skips type inference — the QHP files
mix numeric and string state codes and DuckDB otherwise barfs on the
header row trying to coerce ``"State Code"`` to a number.
"""

from collections.abc import Callable
from pathlib import Path
import tempfile
import zipfile

from cms_api import HEALTHCARE_GOV_DKAN_BASE_URL, DatasetSpec, get_dkan_dataset_zip_url, load_registry
import duckdb
import httpx

from cms_pipelines.defs.resources import resolve_raw_root
from dagster import AssetExecutionContext, AssetsDefinition, MaterializeResult, MetadataValue, asset


_ASSET_PREFIX = "cms_"
# QHP XLSX layout: A1 is "N displayed records", A2 is the header row, data
# starts at A3. Excel's per-sheet row cap is 1,048,576; we use that as the
# row upper bound combined with `stop_at_empty=true` so only populated rows
# come back. Column width varies per file (SHOP Dental has 29 real cols,
# Individual Medical has 149) so we sniff it from the header row rather
# than capping at ``ZZ`` — capping at ``ZZ`` would land hundreds of
# all-null columns in the Parquet.
_XLSX_HEADER_RANGE = "A2:ZZ2"
_XLSX_DATA_RANGE_TEMPLATE = "A2:{last_column}1048576"
_XLSX_MAX_COLUMN_WIDTH = 702  # ZZ in 1-based Excel notation = 26*26 + 26
_HTTP_TIMEOUT_SECONDS = 300.0  # PY2026 Individual Medical is ~60 MB compressed
_HTTP_CHUNK_SIZE = 1 << 20  # 1 MiB; balances syscall overhead against memory


def _resolve_healthcare_gov_zip_url(spec: DatasetSpec) -> str:
    """Look up the ZIP downloadURL for a data.healthcare.gov QHP dataset."""
    if spec.dataset_id is None:
        msg = f"dkan_healthcare_gov_zip dataset {spec.key!r} is missing `dataset_id`"
        raise RuntimeError(msg)
    return get_dkan_dataset_zip_url(spec.dataset_id, base_url=HEALTHCARE_GOV_DKAN_BASE_URL)


_RESOLVERS: dict[str, Callable[[DatasetSpec], str]] = {
    "dkan_healthcare_gov_zip": _resolve_healthcare_gov_zip_url,
}


def _download_zip(*, url: str, dest: Path) -> None:
    """Stream ``url`` to ``dest`` via httpx, raising on any non-2xx status.

    Direct ``urllib`` would also work, but we already depend on httpx
    transitively through ``cms_api`` and it gives us TLS verification,
    sensible defaults, and ``raise_for_status`` consistent with the rest
    of the codebase.
    """
    with httpx.stream("GET", url, timeout=_HTTP_TIMEOUT_SECONDS, follow_redirects=True) as response:
        response.raise_for_status()
        with dest.open("wb") as fp:
            for chunk in response.iter_bytes(_HTTP_CHUNK_SIZE):
                fp.write(chunk)


def _extract_single_xlsx(*, zip_path: Path, dest_dir: Path) -> Path:
    """Extract the lone XLSX from ``zip_path`` into ``dest_dir`` and return its path.

    Every QHP Landscape ZIP packs exactly one ``.xlsx`` member; if CMS
    ever ships a multi-file archive we'd rather fail loudly than silently
    pick the first match and drop the others.
    """
    with zipfile.ZipFile(zip_path) as archive:
        xlsx_members = [name for name in archive.namelist() if name.lower().endswith(".xlsx")]
        if len(xlsx_members) != 1:
            msg = f"expected exactly one .xlsx in {zip_path.name}, found {xlsx_members!r}"
            raise RuntimeError(msg)
        archive.extract(xlsx_members[0], dest_dir)
    return dest_dir / xlsx_members[0]


def _excel_column_letter(n: int) -> str:
    """Map a 1-based column index to Excel column notation (1→A, 27→AA)."""
    if n < 1 or n > _XLSX_MAX_COLUMN_WIDTH:
        msg = f"column index {n} out of supported range 1..{_XLSX_MAX_COLUMN_WIDTH}"
        raise ValueError(msg)
    letters = ""
    while n > 0:
        n, remainder = divmod(n - 1, 26)
        letters = chr(ord("A") + remainder) + letters
    return letters


def _sniff_column_width(con: duckdb.DuckDBPyConnection, xlsx_path: Path) -> int:
    """Return the count of consecutively-populated cells in the header row.

    DuckDB's ``read_xlsx`` doesn't honor an open-ended range, so passing
    ``A2:ZZ1048576`` would back-fill 700 trailing null columns into Parquet
    when (e.g.) SHOP Dental only carries 29 real columns. We read the
    header row once with header=false to find where the populated cells
    end, then pass an exact range to the data read.
    """
    row = con.execute(
        "SELECT * FROM read_xlsx(?, header=false, all_varchar=true, range=?)",
        [str(xlsx_path), _XLSX_HEADER_RANGE],
    ).fetchone()
    if row is None:
        return 0
    for index, value in enumerate(row):
        if value is None:
            return index
    return len(row)


def _run_xlsx_to_parquet(*, xlsx_path: Path, out_path: Path) -> int:
    """Load ``xlsx_path`` into Parquet at ``out_path`` via DuckDB; return rows written.

    DuckDB's ``excel`` extension is auto-installed on first use. We force
    ``all_varchar=true`` because the QHP files mix typed and string-y
    columns and DuckDB's row-1 type inference fails on the header row.
    Downstream dbt models cast the columns they care about; the staging
    layer keeps everything as text so a column-rename in PY2027 doesn't
    require redeploying the extraction asset.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(":memory:") as con:
        con.execute("INSTALL excel; LOAD excel;")
        width = _sniff_column_width(con, xlsx_path)
        if width == 0:
            msg = f"{xlsx_path} has no header row at A2"
            raise RuntimeError(msg)
        data_range = _XLSX_DATA_RANGE_TEMPLATE.format(last_column=_excel_column_letter(width))
        relation = con.sql(
            "SELECT * FROM read_xlsx(?, header=true, all_varchar=true, range=?, stop_at_empty=true)",
            params=[str(xlsx_path), data_range],
        )
        relation.write_parquet(str(out_path))
        row = con.execute("SELECT COUNT(*) FROM read_parquet(?)", [str(out_path)]).fetchone()
    if row is None:
        msg = f"DuckDB returned no count row for {out_path}"
        raise RuntimeError(msg)
    return int(row[0])


def _build_asset(spec: DatasetSpec) -> AssetsDefinition:
    """Return a Dagster asset that streams ``spec``'s QHP ZIP into Parquet."""
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
        zip_url = resolve(spec)
        context.log.info("Downloading %s from %s", asset_name, zip_url)
        with tempfile.TemporaryDirectory(prefix=f"{asset_name}-") as tmp:
            tmp_dir = Path(tmp)
            zip_path = tmp_dir / "download.zip"
            _download_zip(url=zip_url, dest=zip_path)
            xlsx_path = _extract_single_xlsx(zip_path=zip_path, dest_dir=tmp_dir)
            row_count = _run_xlsx_to_parquet(xlsx_path=xlsx_path, out_path=out_path)
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
                "zip_url": MetadataValue.url(zip_url),
            },
        )

    return _generated


# Bind one module-level attribute per QHP registry row so Dagster's
# `load_from_defs_folder` discovers them by name, mirroring the
# `bulk_csv_assets.py` factory. Sources not in `_RESOLVERS` are
# intentionally skipped — they belong to peer modules.
for _spec in load_registry():
    if _spec.source not in _RESOLVERS:
        continue
    globals()[f"{_ASSET_PREFIX}{_spec.key}"] = _build_asset(_spec)
del _spec
