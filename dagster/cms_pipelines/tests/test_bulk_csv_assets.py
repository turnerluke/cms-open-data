"""Materialization tests for the `dkan_data_api_bulk` (bulk-CSV) assets.

The CSV URL the asset normally resolves from the DCAT catalog is
monkey-patched to point at a local fixture file written into ``tmp_path``,
so DuckDB's COPY actually runs end-to-end without any network calls.
``CMS_RAW_ROOT`` is overridden to ``tmp_path`` so the landed Parquet
shows up under a directory the test owns.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, NamedTuple

from cms_api import DatasetSpec, load_registry
from cms_pipelines.defs.cms import bulk_csv_assets
from cms_pipelines.defs.resources import CMS_RAW_ROOT_ENV
import pyarrow.parquet as pq

from dagster import AssetsDefinition, materialize

import pytest


if TYPE_CHECKING:
    from pathlib import Path


SAMPLE_CSV = (
    "rndrng_npi,rndrng_prvdr_last_org_name,rndrng_prvdr_state_abrvtn,bene_unique_cnt\n"
    "1234567890,Hospital A,CA,1200\n"
    "0987654321,Hospital B,TX,950\n"
)


def _write_fixture(tmp_path: Path, content: str = SAMPLE_CSV) -> Path:
    """Write a small CSV fixture and return its absolute path."""
    csv_path = tmp_path / "fixture.csv"
    csv_path.write_text(content)
    return csv_path


_BULK_CSV_SOURCES = {"dkan_data_api_bulk", "dkan_medicaid_bulk", "dkan_open_payments_bulk"}


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


def test_bulk_csv_asset_written_for_every_registry_row() -> None:
    """Every bulk-CSV spec (data.cms.gov DCAT or data.medicaid.gov DKAN) should bind a module attribute."""
    bulk_specs = [s for s in load_registry() if s.source in _BULK_CSV_SOURCES]
    assert bulk_specs, "expected at least one bulk-CSV row"
    for spec in bulk_specs:
        asset_def = _bulk_asset(spec)
        assert isinstance(asset_def, AssetsDefinition)
        assert asset_def.key.path[-1] == f"cms_{spec.key}"


def test_bulk_csv_asset_streams_csv_to_parquet(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """The asset hands the CSV URL to DuckDB and lands one Parquet file with the same rows."""
    csv_path = _write_fixture(tmp_path)
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))

    captured: list[tuple[str, int | None]] = []

    def fake_url(dataset_id: str, *, year: int | None = None) -> str:
        captured.append((dataset_id, year))
        return str(csv_path)

    monkeypatch.setattr(bulk_csv_assets, "get_data_api_csv_url", fake_url)

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    result = materialize([asset_def])

    assert result.success
    assert captured == [(spec.dataset_id, spec.year)]

    parquets = list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))
    assert len(parquets) == 1
    table = pq.read_table(parquets[0])
    assert table.num_rows == 2
    assert "rndrng_npi" in table.column_names


def test_bulk_csv_asset_emits_row_count_metadata(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """`row_count` and `path` metadata are attached to the materialization event."""
    csv_path = _write_fixture(tmp_path)
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    monkeypatch.setattr(
        bulk_csv_assets,
        "get_data_api_csv_url",
        lambda dataset_id, *, year=None: str(csv_path),
    )

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    result = materialize([asset_def])
    materializations = result.asset_materializations_for_node(asset_def.node_def.name)
    assert len(materializations) == 1
    metadata = materializations[0].metadata
    assert metadata["row_count"].value == 2
    assert str(metadata["path"].value).endswith(".parquet")


def test_bulk_csv_asset_refuses_empty_csv(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A header-only CSV (zero data rows) trips the empty-extract guard."""
    csv_path = _write_fixture(tmp_path, "col_a,col_b\n")
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    monkeypatch.setattr(
        bulk_csv_assets,
        "get_data_api_csv_url",
        lambda dataset_id, *, year=None: str(csv_path),
    )

    spec = _bulk_spec()
    asset_def = _bulk_asset(spec)

    with pytest.raises(Exception, match="zero rows"):
        materialize([asset_def])

    # Empty Parquet must not be left behind for dbt to glob into.
    assert not list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))


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
    csv_path = _write_fixture(tmp_path, case.csv_body)
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))

    expected_base_url = getattr(bulk_csv_assets, case.expected_base_url_attr)
    captured: list[tuple[str, str]] = []

    def fake_url(dataset_id: str, *, base_url: str) -> str:
        captured.append((dataset_id, base_url))
        return str(csv_path)

    monkeypatch.setattr(bulk_csv_assets, "get_dkan_dataset_csv_url", fake_url)

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
