"""Tests for dataset-vintage metadata capture."""

from datetime import UTC, date, datetime

from cms_api import DatasetSpec, fetch_dataset_vintage, local_vintage
from cms_api.dkan import HEALTHCARE_GOV_DKAN_BASE_URL, MEDICAID_BASE_URL, OPEN_PAYMENTS_BASE_URL, PROVIDER_DATA_BASE_URL
from cms_api.vintage import _coerce_date, _parse_temporal
import respx

import pytest


PROVIDER_DATASET_ID = "xubh-q36u"
PROVIDER_METASTORE_URL = f"{PROVIDER_DATA_BASE_URL}/provider-data/api/1/metastore/schemas/dataset/items/{PROVIDER_DATASET_ID}"
BULK_DATASET_UUID = "7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b"
DATA_JSON_URL = f"{PROVIDER_DATA_BASE_URL}/data.json"
MEDICAID_UUID = "d890d3a9-6b00-43fd-8b31-fcba4c8e2909"
OPEN_PAYMENTS_UUID = "9ac4f7f8-b6e4-4d80-8410-4aba7e71dd02"
QHP_UUID = "6fe7fb77-7291-4104-952f-7c7e2c5d0c45"


def _provider_spec() -> DatasetSpec:
    """Build a Care Compare (Provider Data Catalog) fixture spec."""
    return DatasetSpec(
        key="hospital_general_information",
        source="dkan_provider_data",
        dataset_id=PROVIDER_DATASET_ID,
        description="Fixture.",
        group="cms_raw_provider_compare",
    )


def _bulk_spec(year: int | None = None) -> DatasetSpec:
    """Build a data-api/v1 bulk-CSV fixture spec, optionally pinned to a year."""
    return DatasetSpec(
        key="part_d_spending_by_drug",
        source="dkan_data_api_bulk",
        dataset_id=BULK_DATASET_UUID,
        description="Fixture.",
        group="cms_raw_drug_spending",
        year=year,
    )


def _data_json_payload() -> dict[str, object]:
    """Build a DCAT catalog with one dataset carrying two yearly CSV distributions."""
    return {
        "dataset": [
            {
                "identifier": f"https://data.cms.gov/data-api/v1/dataset/{BULK_DATASET_UUID}/data-viewer",
                "modified": "2026-06-25",
                "issued": "2021-01-15",
                "temporal": "2024-01-01/2024-12-31",
                "distribution": [
                    {
                        "mediaType": "text/csv",
                        "downloadURL": "https://data.cms.gov/files/dy23.csv",
                        "modified": "2025-06-01",
                        "temporal": "2023-01-01/2023-12-31",
                    },
                    {
                        "mediaType": "text/csv",
                        "downloadURL": "https://data.cms.gov/files/dy24.csv",
                        "modified": "2026-06-25",
                        "temporal": "2024-01-01/2024-12-31",
                    },
                    {"format": "API", "accessURL": "https://data.cms.gov/api"},
                ],
            },
        ],
    }


def test_coerce_date_handles_dates_timestamps_and_junk() -> None:
    """Bare dates and timestamp prefixes parse; junk becomes None."""
    assert _coerce_date("2026-07-22") == date(2026, 7, 22)
    assert _coerce_date("2026-07-13T15:43:41+00:00") == date(2026, 7, 13)
    assert _coerce_date("R/P1Y") is None
    assert _coerce_date("2026-13-99T00:00:00") is None
    assert _coerce_date(None) is None
    assert _coerce_date(20260722) is None


def test_parse_temporal_splits_range() -> None:
    """A DCAT temporal range splits into start and end dates."""
    assert _parse_temporal("2024-01-01/2024-12-31") == (date(2024, 1, 1), date(2024, 12, 31))
    assert _parse_temporal("not-a-range") == (None, None)
    assert _parse_temporal(None) == (None, None)


@respx.mock
def test_provider_data_vintage_reads_metastore_dates() -> None:
    """Care Compare vintages carry the metastore's modified/issued/released dates."""
    respx.get(PROVIDER_METASTORE_URL).respond(
        json={
            "identifier": PROVIDER_DATASET_ID,
            "issued": "2025-01-08",
            "modified": "2026-07-22",
            "released": "2026-08-13",
        },
    )

    vintage = fetch_dataset_vintage(_provider_spec())

    assert vintage.dataset_key == "hospital_general_information"
    assert vintage.source_family == "dkan_provider_data"
    assert vintage.dataset_id == PROVIDER_DATASET_ID
    assert vintage.modified == date(2026, 7, 22)
    assert vintage.issued == date(2025, 1, 8)
    assert vintage.released == date(2026, 8, 13)
    assert vintage.temporal_start is None
    assert vintage.captured_at.tzinfo is not None


@respx.mock
def test_provider_data_vintage_rejects_non_object_payload() -> None:
    """A non-object metastore payload raises instead of landing empty metadata."""
    respx.get(PROVIDER_METASTORE_URL).respond(json=["not", "an", "object"])

    with pytest.raises(TypeError, match="metastore record"):
        fetch_dataset_vintage(_provider_spec())


@respx.mock
def test_data_api_vintage_uses_latest_csv_distribution() -> None:
    """Without a year pin, the latest yearly CSV's modified/temporal win."""
    respx.get(DATA_JSON_URL).respond(json=_data_json_payload())

    vintage = fetch_dataset_vintage(_bulk_spec())

    assert vintage.modified == date(2026, 6, 25)
    assert vintage.temporal_start == date(2024, 1, 1)
    assert vintage.temporal_end == date(2024, 12, 31)
    assert vintage.issued == date(2021, 1, 15)


@respx.mock
def test_data_api_vintage_honors_year_pin() -> None:
    """A year-pinned spec reads the matching distribution's dates."""
    respx.get(DATA_JSON_URL).respond(json=_data_json_payload())

    vintage = fetch_dataset_vintage(_bulk_spec(year=2023))

    assert vintage.modified == date(2025, 6, 1)
    assert vintage.temporal_start == date(2023, 1, 1)
    assert vintage.temporal_end == date(2023, 12, 31)


@respx.mock
def test_data_api_vintage_falls_back_to_dataset_dates() -> None:
    """With no CSV distribution at all, dataset-level modified/temporal apply."""
    payload = _data_json_payload()
    dataset = payload["dataset"][0]  # type: ignore[index]
    dataset["distribution"] = []
    respx.get(DATA_JSON_URL).respond(json=payload)

    vintage = fetch_dataset_vintage(_bulk_spec())

    assert vintage.modified == date(2026, 6, 25)
    assert vintage.temporal_start == date(2024, 1, 1)


@pytest.mark.parametrize(
    ("source", "dataset_id", "base_url"),
    [
        ("dkan_medicaid_bulk", MEDICAID_UUID, MEDICAID_BASE_URL),
        ("dkan_open_payments_bulk", OPEN_PAYMENTS_UUID, OPEN_PAYMENTS_BASE_URL),
        ("dkan_healthcare_gov_zip", QHP_UUID, HEALTHCARE_GOV_DKAN_BASE_URL),
    ],
)
@respx.mock
def test_bare_metastore_vintage_reads_dates(source: str, dataset_id: str, base_url: str) -> None:
    """Bare-metastore DKAN hosts share one fetch path; timestamps truncate to dates."""
    respx.get(f"{base_url}/api/1/metastore/schemas/dataset/items/{dataset_id}").respond(
        json={
            "identifier": dataset_id,
            "issued": "2023-12-01T13:38:29+00:00",
            "modified": "2026-07-13T15:43:41+00:00",
        },
    )
    spec = DatasetSpec(
        key="fixture_dataset",
        source=source,  # type: ignore[arg-type]
        dataset_id=dataset_id,
        description="Fixture.",
        group="cms_raw",
    )

    vintage = fetch_dataset_vintage(spec)

    assert vintage.modified == date(2026, 7, 13)
    assert vintage.issued == date(2023, 12, 1)
    assert vintage.released is None


def test_healthcare_gov_vintage_is_local_only() -> None:
    """Sources with no upstream metadata get capture-time-only vintages, offline."""
    spec = DatasetSpec(
        key="healthcare_gov_glossary",
        source="healthcare_gov",
        path="/api/glossary.json",
        description="Fixture.",
        group="cms_raw",
    )

    before = datetime.now(tz=UTC)
    vintage = fetch_dataset_vintage(spec)

    assert vintage.modified is None
    assert vintage.issued is None
    assert vintage.temporal_start is None
    assert before <= vintage.captured_at <= datetime.now(tz=UTC)


def test_local_vintage_carries_identity_fields() -> None:
    """`local_vintage` fills identity fields and leaves upstream dates null."""
    vintage = local_vintage("nppes_providers", "nppes")

    assert vintage.dataset_key == "nppes_providers"
    assert vintage.source_family == "nppes"
    assert vintage.dataset_id is None
    assert vintage.modified is None
