"""Materialization tests for the `dkan_data_api_bulk` (bulk-CSV) assets.

The CSV URL the asset normally resolves from the DCAT catalog is
monkey-patched to a synthetic https URL, and `respx` intercepts the
httpx GET so the fixture bytes stream through the real download-to-temp
path without any network calls. ``CMS_RAW_ROOT`` is overridden to
``tmp_path`` so the landed Parquet shows up under a directory the test
owns.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, NamedTuple

from cms_api import DatasetSpec, load_registry
from cms_pipelines.defs.cms import bulk_csv_assets
from cms_pipelines.defs.resources import CMS_RAW_ROOT_ENV
import httpx
import pyarrow.parquet as pq
import respx

from dagster import AssetsDefinition, materialize

import pytest


if TYPE_CHECKING:
    from pathlib import Path


SAMPLE_CSV = (
    "rndrng_npi,rndrng_prvdr_last_org_name,rndrng_prvdr_state_abrvtn,bene_unique_cnt\n"
    "1234567890,Hospital A,CA,1200\n"
    "0987654321,Hospital B,TX,950\n"
)

# A stable synthetic URL the resolver monkey-patch returns and respx
# routes on. The host is arbitrary — respx swaps in the mock transport.
FAKE_CSV_URL = "https://fixture.test/bulk.csv"


_BULK_CSV_SOURCES = {
    "dkan_data_api_bulk",
    "dkan_medicaid_bulk",
    "dkan_open_payments_bulk",
    "dkan_provider_bulk",
}


_SIMULATED_CONVERT_MESSAGE = "simulated convert failure"


class _SimulatedConvertError(RuntimeError):
    """Raised by the convert-failure test to force `_run_bulk_load` into its `finally`."""

    def __init__(self) -> None:
        super().__init__(_SIMULATED_CONVERT_MESSAGE)


def _bulk_spec() -> DatasetSpec:
    """Pick a `dkan_data_api_bulk` spec out of the registry for these tests."""
    specs = [s for s in load_registry() if s.source == "dkan_data_api_bulk"]
    assert specs, "expected at least one dkan_data_api_bulk row in datasets.toml"
    return specs[0]


def _spec_for_source(source: str) -> DatasetSpec:
    """Pick the first registry spec whose `source` matches."""
    specs = [s for s in load_registry() if s.source == source]
    assert specs, f"expected at least one {source} row in datasets.toml"
    return specs[0]


def _bulk_asset(spec: DatasetSpec) -> AssetsDefinition:
    """Look up the generated bulk-CSV asset for `spec` by its canonical name."""
    return getattr(bulk_csv_assets, f"cms_{spec.key}")


def _serve_csv(mock: respx.MockRouter, body: str, url: str = FAKE_CSV_URL) -> None:
    """Route an httpx GET for `url` to a 200 response with `body` bytes."""
    mock.get(url).mock(return_value=httpx.Response(200, content=body.encode()))


def test_bulk_csv_asset_written_for_every_registry_row() -> None:
    """Every bulk-CSV spec (data.cms.gov DCAT or data.medicaid.gov DKAN) should bind a module attribute."""
    bulk_specs = [s for s in load_registry() if s.source in _BULK_CSV_SOURCES]
    assert bulk_specs, "expected at least one bulk-CSV row"
    for spec in bulk_specs:
        asset_def = _bulk_asset(spec)
        assert isinstance(asset_def, AssetsDefinition)
        assert asset_def.key.path[-1] == f"cms_{spec.key}"


@respx.mock
def test_bulk_csv_asset_streams_csv_to_parquet(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Asset downloads CSV via httpx, DuckDB converts it, Parquet lands with same rows."""
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))

    captured: list[tuple[str, int | None]] = []

    def fake_url(dataset_id: str, *, year: int | None = None) -> str:
        captured.append((dataset_id, year))
        return FAKE_CSV_URL

    monkeypatch.setattr(bulk_csv_assets, "get_data_api_csv_url", fake_url)
    _serve_csv(respx.mock, SAMPLE_CSV)

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    result = materialize([asset_def])

    assert result.success
    assert captured == [(spec.dataset_id, spec.year)]

    asset_dir = tmp_path / f"cms_{spec.key}"
    parquets = list(asset_dir.glob("*.parquet"))
    assert len(parquets) == 1
    table = pq.read_table(parquets[0])
    assert table.num_rows == 2
    assert "rndrng_npi" in table.column_names

    # The download temp file must not survive a successful convert.
    assert not list(asset_dir.glob(".*.csv.download"))


@respx.mock
def test_bulk_csv_asset_rematerialization_leaves_one_file(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Re-running the asset replaces the landed Parquet instead of accumulating runs."""
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    monkeypatch.setattr(
        bulk_csv_assets,
        "get_data_api_csv_url",
        lambda dataset_id, *, year=None: FAKE_CSV_URL,
    )

    _serve_csv(respx.mock, SAMPLE_CSV)
    assert materialize([asset_def]).success

    respx.mock.reset()
    _serve_csv(
        respx.mock,
        "rndrng_npi,rndrng_prvdr_last_org_name,rndrng_prvdr_state_abrvtn,bene_unique_cnt\n1111111111,Hospital C,NY,400\n",
    )
    assert materialize([asset_def]).success

    parquets = list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))
    assert len(parquets) == 1
    table = pq.read_table(parquets[0])
    assert table.num_rows == 1
    assert table.column("rndrng_npi").to_pylist() == [1111111111]


@respx.mock
def test_bulk_csv_asset_emits_row_count_metadata(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """`row_count` and `path` metadata are attached to the materialization event."""
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    monkeypatch.setattr(
        bulk_csv_assets,
        "get_data_api_csv_url",
        lambda dataset_id, *, year=None: FAKE_CSV_URL,
    )
    _serve_csv(respx.mock, SAMPLE_CSV)

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    result = materialize([asset_def])
    materializations = result.asset_materializations_for_node(asset_def.node_def.name)
    assert len(materializations) == 1
    metadata = materializations[0].metadata
    assert metadata["row_count"].value == 2
    assert str(metadata["path"].value).endswith(".parquet")


@respx.mock
def test_bulk_csv_asset_refuses_empty_csv(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A header-only CSV (zero data rows) trips the empty-extract guard."""
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    monkeypatch.setattr(
        bulk_csv_assets,
        "get_data_api_csv_url",
        lambda dataset_id, *, year=None: FAKE_CSV_URL,
    )
    _serve_csv(respx.mock, "col_a,col_b\n")

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    with pytest.raises(Exception, match="zero rows"):
        materialize([asset_def])

    # Empty Parquet must not be left behind for dbt to glob into, the
    # failed run's staged file must not leak, and the download temp
    # file must have been cleaned up by the `finally` guard.
    asset_dir = tmp_path / f"cms_{spec.key}"
    assert not list(asset_dir.glob("*.parquet"))
    assert not list(asset_dir.glob(".*.tmp"))
    assert not list(asset_dir.glob(".*.csv.download"))


@respx.mock
def test_bulk_csv_temp_file_cleaned_up_on_conversion_failure(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A DuckDB conversion failure must still delete the downloaded temp file."""
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    monkeypatch.setattr(
        bulk_csv_assets,
        "get_data_api_csv_url",
        lambda dataset_id, *, year=None: FAKE_CSV_URL,
    )
    # Serve non-CSV garbage; the CSV sniffer can still parse it as one
    # column, so force the failure by replacing `read_csv` on the module
    # `duckdb` binding with a raiser once the download has happened.
    _serve_csv(respx.mock, "some bytes that would parse\n")

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)
    asset_dir = tmp_path / f"cms_{spec.key}"

    def failing_connect(*args: object, **kwargs: object) -> object:
        # At this point the temp download file should already exist —
        # assert that, then blow up to prove the `finally` cleanup runs
        # on convert-time errors, not just on download-time errors.
        assert list(asset_dir.glob(".*.csv.download")), "download temp file should exist before DuckDB convert"
        raise _SimulatedConvertError

    monkeypatch.setattr(bulk_csv_assets.duckdb, "connect", failing_connect)

    with pytest.raises(Exception, match=_SIMULATED_CONVERT_MESSAGE):
        materialize([asset_def])

    assert not list(asset_dir.glob(".*.csv.download"))
    assert not list(asset_dir.glob("*.parquet"))


@respx.mock
def test_bulk_csv_full_file_sniff_handles_late_type_flip(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A column that looks numeric for many rows then flips to text must land as VARCHAR.

    Proves `sample_size=-1` (full-file type sniffing) is in effect. With
    DuckDB's default 20 000-row sample, a column with 30 000 numeric
    rows followed by an alphanumeric row would be sniffed as BIGINT and
    the convert would error partway through.
    """
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    monkeypatch.setattr(
        bulk_csv_assets,
        "get_data_api_csv_url",
        lambda dataset_id, *, year=None: FAKE_CSV_URL,
    )

    numeric_rows = 30_000
    lines = ["postal_code,name"]
    lines.extend(f"{90000 + i},row_{i}" for i in range(numeric_rows))
    lines.append("SW1A1AA,uk_postcode_row")
    _serve_csv(respx.mock, "\n".join(lines) + "\n")

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    result = materialize([asset_def])
    assert result.success

    parquets = list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))
    assert len(parquets) == 1
    table = pq.read_table(parquets[0])
    assert table.num_rows == numeric_rows + 1
    # The critical assertion: full-file sniff kept the column as text so
    # the UK postcode row didn't error out mid-conversion.
    assert str(table.schema.field("postal_code").type) == "string"
    assert table.column("postal_code").to_pylist()[-1] == "SW1A1AA"


class _BareMetastoreCase(NamedTuple):
    """One parametrized scenario for the bare-metastore (host-routed) bulk asset test."""

    source: str
    expected_base_url_attr: str
    csv_body: str
    expected_column: str


_BARE_METASTORE_CASES = [
    _BareMetastoreCase(
        source="dkan_medicaid_bulk",
        expected_base_url_attr="MEDICAID_BASE_URL",
        csv_body=(
            "state,utilization_type,product_name,ndc,units_reimbursed\n"
            "CA,FFSU,DRUGA,00000000001,100\n"
            "TX,FFSU,DRUGB,00000000002,250\n"
        ),
        expected_column="ndc",
    ),
    _BareMetastoreCase(
        source="dkan_open_payments_bulk",
        expected_base_url_attr="OPEN_PAYMENTS_BASE_URL",
        csv_body=(
            "Change_Type,Physician_Profile_ID,Recipient_State,Total_Amount_of_Payment_USDollars\n"
            "NEW,12345,CA,1500.00\n"
            "NEW,67890,TX,2750.00\n"
        ),
        expected_column="Physician_Profile_ID",
    ),
]


@pytest.mark.parametrize("case", _BARE_METASTORE_CASES, ids=["medicaid", "open_payments"])
@respx.mock
def test_bare_metastore_bulk_asset_streams_csv_to_parquet(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    case: _BareMetastoreCase,
) -> None:
    """Both bare-metastore sources route through `get_dkan_dataset_csv_url` with the correct host.

    The single function fans out to either ``MEDICAID_BASE_URL`` or
    ``OPEN_PAYMENTS_BASE_URL`` based on the resolver wired up in
    ``bulk_csv_assets._RESOLVERS``; this test verifies both end up
    requesting the correct host.
    """
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))

    expected_base_url = getattr(bulk_csv_assets, case.expected_base_url_attr)
    captured: list[tuple[str, str]] = []

    def fake_url(dataset_id: str, *, base_url: str) -> str:
        captured.append((dataset_id, base_url))
        return FAKE_CSV_URL

    monkeypatch.setattr(bulk_csv_assets, "get_dkan_dataset_csv_url", fake_url)
    _serve_csv(respx.mock, case.csv_body)

    spec = _spec_for_source(case.source)
    asset_def = _bulk_asset(spec)

    result = materialize([asset_def])

    assert result.success
    assert captured == [(spec.dataset_id, expected_base_url)]
    parquets = list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))
    assert len(parquets) == 1
    table = pq.read_table(parquets[0])
    assert table.num_rows == 2
    assert case.expected_column in table.column_names


@respx.mock
def test_provider_bulk_asset_streams_csv_to_parquet(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """`dkan_provider_bulk` rows resolve via `get_provider_data_csv_url` (no host param).

    Confirms the Doctors & Clinicians files (millions of rows each) now
    ride the bulk-CSV factory rather than the JSON-paginated one, which
    is what avoids the rate-limit storm on data.cms.gov that the change
    exists to fix.
    """
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))

    captured: list[str] = []

    def fake_url(dataset_id: str) -> str:
        captured.append(dataset_id)
        return FAKE_CSV_URL

    monkeypatch.setattr(bulk_csv_assets, "get_provider_data_csv_url", fake_url)
    # Provider Data Catalog CSVs ship with "human" headers (title case
    # + spaces); the asset relies on `normalize_names=True` to land
    # snake_case column names because the dbt staging models (and the
    # previously hand-seeded parquets) use snake_case.
    _serve_csv(
        respx.mock,
        "NPI,Provider Last Name,Provider First Name\n1234567890,Doe,Jane\n0987654321,Roe,John\n",
    )

    spec = _spec_for_source("dkan_provider_bulk")
    asset_def = _bulk_asset(spec)

    result = materialize([asset_def])

    assert result.success
    assert captured == [spec.dataset_id]
    parquets = list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))
    assert len(parquets) == 1
    table = pq.read_table(parquets[0])
    assert table.num_rows == 2
    # Load-bearing: original CSV headers ("NPI", "Provider Last Name")
    # must land as snake_case ("npi", "provider_last_name") so dbt's
    # `stg_cms__doctors_and_clinicians_*` staging models read them by
    # the same names they used against the seeded parquets.
    assert "npi" in table.column_names
    assert "provider_last_name" in table.column_names
    assert "NPI" not in table.column_names
