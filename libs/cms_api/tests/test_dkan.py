"""Tests for the DKAN Provider Data Catalog client."""

from cms_api.dkan import (
    MEDICAID_BASE_URL,
    OPEN_PAYMENTS_BASE_URL,
    PROVIDER_DATA_BASE_URL,
    get_data_api_csv_url,
    get_dkan_dataset_csv_url,
    iter_provider_data_catalog,
)
import httpx
import respx

import pytest


DATASET_ID = "xubh-q36u"  # Hospital General Information
DISTRIBUTION_ID = "11111111-2222-3333-4444-555555555555"
METASTORE_PATH = f"/provider-data/api/1/metastore/schemas/dataset/items/{DATASET_ID}"
DATASTORE_PATH = f"/provider-data/api/1/datastore/query/{DISTRIBUTION_ID}"
DATA_JSON_PATH = "/data.json"
BULK_DATASET_UUID = "8889d81e-2ee7-448f-8713-f071038289b5"
BULK_CSV_URL_2023 = "https://data.cms.gov/sites/default/files/2024-05/uuid-2023/MUP_PHY_2023.csv"
BULK_CSV_URL_2024 = "https://data.cms.gov/sites/default/files/2026-05/uuid-2024/MUP_PHY_2024.csv"
MEDICAID_SDUD_UUID = "d890d3a9-6b00-43fd-8b31-fcba4c8e2909"
MEDICAID_METASTORE_PATH = f"/api/1/metastore/schemas/dataset/items/{MEDICAID_SDUD_UUID}"
MEDICAID_SDUD_CSV_URL = "https://download.medicaid.gov/data/sdud-2023-updated.csv"
OPEN_PAYMENTS_OWNERSHIP_UUID = "9ac4f7f8-b6e4-4d80-8410-4aba7e71dd02"
OPEN_PAYMENTS_METASTORE_PATH = f"/api/1/metastore/schemas/dataset/items/{OPEN_PAYMENTS_OWNERSHIP_UUID}"
OPEN_PAYMENTS_OWNERSHIP_CSV_URL = (
    "https://download.cms.gov/openpayments/PGYR2024_P01232026_01102026/OP_DTL_OWNRSHP_PGYR2024_P01232026_01102026.csv"
)


def _metastore_payload(distribution_id: str = DISTRIBUTION_ID) -> dict[str, object]:
    """Return a metastore record whose first distribution carries `distribution_id`."""
    return {
        "identifier": DATASET_ID,
        "title": "Hospital General Information",
        "distribution": [
            {"identifier": distribution_id, "title": "Hospital General Information CSV"},
        ],
    }


def _stub_metastore(distribution_id: str = DISTRIBUTION_ID) -> None:
    """Install a respx route that returns a metastore record for DATASET_ID."""
    respx.get(f"{PROVIDER_DATA_BASE_URL}{METASTORE_PATH}").respond(
        json=_metastore_payload(distribution_id),
    )


@respx.mock
def test_iter_provider_data_catalog_happy_path_yields_each_row() -> None:
    """A single-page response yields one dict per row."""
    _stub_metastore()
    respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").respond(
        json={
            "results": [
                {"facility_id": "010001", "facility_name": "Hospital A"},
                {"facility_id": "010002", "facility_name": "Hospital B"},
            ],
        },
    )

    rows = list(iter_provider_data_catalog(DATASET_ID))

    assert len(rows) == 2
    assert rows[0]["facility_name"] == "Hospital A"
    assert rows[1]["facility_id"] == "010002"


@respx.mock
def test_iter_provider_data_catalog_paginates_until_short_page() -> None:
    """Pagination keeps going while a full batch comes back, stops on a short one."""
    _stub_metastore()
    page_a = {"results": [{"id": "0"}, {"id": "1"}]}
    page_b = {"results": [{"id": "2"}]}  # short page → loop exits

    route = respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").mock(
        side_effect=[
            httpx.Response(200, json=page_a),
            httpx.Response(200, json=page_b),
        ],
    )

    rows = list(iter_provider_data_catalog(DATASET_ID, batch_size=2))

    assert [r["id"] for r in rows] == ["0", "1", "2"]
    assert route.call_count == 2
    assert dict(route.calls[0].request.url.params)["offset"] == "0"
    assert dict(route.calls[0].request.url.params)["limit"] == "2"
    assert dict(route.calls[1].request.url.params)["offset"] == "2"


@respx.mock
def test_iter_provider_data_catalog_stops_on_empty_result() -> None:
    """An empty `results` array terminates iteration without raising."""
    _stub_metastore()
    route = respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").respond(
        json={"results": []},
    )

    rows = list(iter_provider_data_catalog(DATASET_ID, batch_size=10))

    assert rows == []
    assert route.call_count == 1


@respx.mock
def test_iter_provider_data_catalog_passes_show_reference_ids_to_metastore() -> None:
    """The metastore call must include `show-reference-ids` or `distribution[].identifier` is missing.

    Without this query parameter, DKAN returns the de-referenced
    `dcat:Distribution` fields (downloadURL, mediaType, …) but omits the
    UUID we need to query the datastore — so this is load-bearing.
    """
    metastore_route = respx.get(f"{PROVIDER_DATA_BASE_URL}{METASTORE_PATH}").respond(
        json=_metastore_payload(),
    )
    respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").respond(
        json={"results": [{"id": "0"}]},
    )

    list(iter_provider_data_catalog(DATASET_ID, batch_size=10))

    assert "show-reference-ids" in dict(metastore_route.calls.last.request.url.params)


@respx.mock
def test_iter_provider_data_catalog_resolves_current_distribution_id() -> None:
    """The datastore is queried by the live `distribution[0].identifier`, not the dataset UUID."""
    new_distribution_id = "abcdef00-1111-2222-3333-444455556666"
    _stub_metastore(distribution_id=new_distribution_id)
    datastore_path = f"/provider-data/api/1/datastore/query/{new_distribution_id}"
    route = respx.get(f"{PROVIDER_DATA_BASE_URL}{datastore_path}").respond(
        json={"results": [{"id": "0"}]},
    )

    rows = list(iter_provider_data_catalog(DATASET_ID, batch_size=10))

    assert rows == [{"id": "0"}]
    assert route.call_count == 1


@respx.mock
def test_iter_provider_data_catalog_raises_on_missing_distribution() -> None:
    """A metastore record with no distributions can't be queried — fail loudly."""
    respx.get(f"{PROVIDER_DATA_BASE_URL}{METASTORE_PATH}").respond(
        json={"identifier": DATASET_ID, "distribution": []},
    )

    with pytest.raises(ValueError, match="no distributions"):
        list(iter_provider_data_catalog(DATASET_ID))


@respx.mock
def test_iter_provider_data_catalog_raises_on_missing_identifier() -> None:
    """A distribution entry without a string identifier is malformed."""
    respx.get(f"{PROVIDER_DATA_BASE_URL}{METASTORE_PATH}").respond(
        json={"identifier": DATASET_ID, "distribution": [{"title": "no identifier here"}]},
    )

    with pytest.raises(ValueError, match="identifier"):
        list(iter_provider_data_catalog(DATASET_ID))


@respx.mock
def test_iter_provider_data_catalog_rejects_non_object_metastore() -> None:
    """The metastore must return an object — anything else is a server bug."""
    respx.get(f"{PROVIDER_DATA_BASE_URL}{METASTORE_PATH}").respond(json=["unexpected"])

    with pytest.raises(TypeError, match="metastore payload"):
        list(iter_provider_data_catalog(DATASET_ID))


@respx.mock
def test_iter_provider_data_catalog_rejects_non_object_datastore_page() -> None:
    """The datastore must return an object wrapping `results`; arrays are malformed."""
    _stub_metastore()
    respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").respond(json=[{"id": "0"}])

    with pytest.raises(TypeError, match="datastore page"):
        list(iter_provider_data_catalog(DATASET_ID, batch_size=10))


@respx.mock
def test_iter_provider_data_catalog_rejects_non_object_row() -> None:
    """A scalar inside `results` would mean a malformed response."""
    _stub_metastore()
    respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").respond(
        json={"results": ["not-a-dict"]},
    )

    with pytest.raises(TypeError, match="datastore row"):
        list(iter_provider_data_catalog(DATASET_ID, batch_size=10))


@respx.mock
def test_iter_provider_data_catalog_retries_on_5xx_then_succeeds() -> None:
    """Transient 503 on the datastore is retried; the eventual 200 page is yielded."""
    _stub_metastore()
    route = respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").mock(
        side_effect=[
            httpx.Response(503, json={"error": "down"}),
            httpx.Response(200, json={"results": [{"id": "0"}]}),
        ],
    )

    rows = list(iter_provider_data_catalog(DATASET_ID, batch_size=10))

    assert rows == [{"id": "0"}]
    assert route.call_count == 2


@respx.mock
def test_iter_provider_data_catalog_does_not_retry_on_4xx() -> None:
    """A 404 (e.g. stale distribution id) surfaces immediately."""
    _stub_metastore()
    route = respx.get(f"{PROVIDER_DATA_BASE_URL}{DATASTORE_PATH}").respond(404)

    with pytest.raises(httpx.HTTPStatusError):
        list(iter_provider_data_catalog(DATASET_ID, batch_size=10))

    assert route.call_count == 1


# ---------------------------------------------------------------------------
# get_data_api_csv_url — DCAT-catalog-based CSV resolution
# ---------------------------------------------------------------------------


def _csv_distribution(
    *,
    year: int,
    url: str,
    media_type: str | None = "text/csv",
) -> dict[str, object]:
    """Build a fake DCAT distribution shaped like the real `data.json` entries."""
    entry: dict[str, object] = {
        "@type": "dcat:Distribution",
        "title": f"Medicare Physician — by Provider : {year}-12-01",
        "modified": f"{year + 1}-05-21",
        "temporal": f"{year}-01-01/{year}-12-31",
        "downloadURL": url,
    }
    if media_type is not None:
        entry["mediaType"] = media_type
    return entry


def _data_json_payload(
    *, dataset_uuid: str = BULK_DATASET_UUID, distributions: list[dict[str, object]] | None = None
) -> dict[str, object]:
    """Wrap a list of distributions in the DCAT envelope `data.json` returns."""
    return {
        "@context": "https://project-open-data.cfo.gov/v1.1/schema/catalog.jsonld",
        "@type": "dcat:Catalog",
        "dataset": [
            {
                "@type": "dcat:Dataset",
                "title": "Medicare Physician & Other Practitioners — by Provider",
                "identifier": f"https://data.cms.gov/data-api/v1/dataset/{dataset_uuid}/data-viewer",
                "distribution": distributions if distributions is not None else [],
            },
        ],
    }


def _stub_data_json(payload: dict[str, object]) -> None:
    """Install a respx route that serves a fake DCAT payload at /data.json."""
    respx.get(f"{PROVIDER_DATA_BASE_URL}{DATA_JSON_PATH}").respond(json=payload)


@respx.mock
def test_get_data_api_csv_url_returns_latest_year_by_default() -> None:
    """With no `year=` argument, the highest-year CSV distribution wins."""
    _stub_data_json(
        _data_json_payload(
            distributions=[
                _csv_distribution(year=2023, url=BULK_CSV_URL_2023),
                _csv_distribution(year=2024, url=BULK_CSV_URL_2024),
            ],
        ),
    )

    assert get_data_api_csv_url(BULK_DATASET_UUID) == BULK_CSV_URL_2024


@respx.mock
def test_get_data_api_csv_url_honors_explicit_year() -> None:
    """An explicit `year=` selects that exact distribution, not the latest."""
    _stub_data_json(
        _data_json_payload(
            distributions=[
                _csv_distribution(year=2023, url=BULK_CSV_URL_2023),
                _csv_distribution(year=2024, url=BULK_CSV_URL_2024),
            ],
        ),
    )

    assert get_data_api_csv_url(BULK_DATASET_UUID, year=2023) == BULK_CSV_URL_2023


@respx.mock
def test_get_data_api_csv_url_ignores_non_csv_distributions() -> None:
    """Distributions without `mediaType: text/csv` are skipped silently."""
    pdf_url = "https://data.cms.gov/sites/default/files/2024/data_dictionary.pdf"
    _stub_data_json(
        _data_json_payload(
            distributions=[
                {
                    "@type": "dcat:Distribution",
                    "title": "Data Dictionary",
                    "mediaType": "application/pdf",
                    "downloadURL": pdf_url,
                    "temporal": "2023-01-01/2023-12-31",
                },
                _csv_distribution(year=2023, url=BULK_CSV_URL_2023),
            ],
        ),
    )

    assert get_data_api_csv_url(BULK_DATASET_UUID) == BULK_CSV_URL_2023


@respx.mock
def test_get_data_api_csv_url_skips_distributions_without_download_url() -> None:
    """API-only `accessURL` entries (no direct file) are filtered out."""
    _stub_data_json(
        _data_json_payload(
            distributions=[
                {
                    "@type": "dcat:Distribution",
                    "title": "API entry",
                    "mediaType": "text/csv",
                    "accessURL": "https://data.cms.gov/data-api/v1/dataset-resources/abc",
                    "temporal": "2024-01-01/2024-12-31",
                },
                _csv_distribution(year=2023, url=BULK_CSV_URL_2023),
            ],
        ),
    )

    assert get_data_api_csv_url(BULK_DATASET_UUID) == BULK_CSV_URL_2023


@respx.mock
def test_get_data_api_csv_url_raises_when_dataset_missing() -> None:
    """A UUID not present in `data.json` is a `KeyError`, not a transport error."""
    _stub_data_json({"@type": "dcat:Catalog", "dataset": []})

    with pytest.raises(KeyError, match=r"data\.json"):
        get_data_api_csv_url(BULK_DATASET_UUID)


@respx.mock
def test_get_data_api_csv_url_raises_when_no_csv_distribution() -> None:
    """A dataset with only non-CSV distributions raises `KeyError` (not silent fallback)."""
    _stub_data_json(
        _data_json_payload(
            distributions=[
                {
                    "@type": "dcat:Distribution",
                    "mediaType": "application/pdf",
                    "downloadURL": "https://data.cms.gov/x.pdf",
                    "temporal": "2024-01-01/2024-12-31",
                },
            ],
        ),
    )

    with pytest.raises(KeyError, match="no CSV distribution"):
        get_data_api_csv_url(BULK_DATASET_UUID)


@respx.mock
def test_get_data_api_csv_url_raises_when_year_unavailable() -> None:
    """An explicit `year=` for which no CSV exists raises `KeyError` listing available years."""
    _stub_data_json(
        _data_json_payload(
            distributions=[_csv_distribution(year=2023, url=BULK_CSV_URL_2023)],
        ),
    )

    with pytest.raises(KeyError, match="2024"):
        get_data_api_csv_url(BULK_DATASET_UUID, year=2024)


@respx.mock
def test_get_data_api_csv_url_rejects_non_object_payload() -> None:
    """A top-level array `data.json` is a malformed response — surface it loudly."""
    respx.get(f"{PROVIDER_DATA_BASE_URL}{DATA_JSON_PATH}").respond(json=["unexpected"])

    with pytest.raises(TypeError, match=r"data\.json"):
        get_data_api_csv_url(BULK_DATASET_UUID)


@respx.mock
def test_get_data_api_csv_url_rejects_non_list_dataset_field() -> None:
    """`dataset` must be a list — anything else is malformed."""
    respx.get(f"{PROVIDER_DATA_BASE_URL}{DATA_JSON_PATH}").respond(
        json={"@type": "dcat:Catalog", "dataset": {"oops": "object"}},
    )

    with pytest.raises(TypeError, match="dataset"):
        get_data_api_csv_url(BULK_DATASET_UUID)


@respx.mock
def test_get_data_api_csv_url_ignores_distributions_without_year() -> None:
    """A distribution missing `temporal` (or with a non-year value) is skipped."""
    _stub_data_json(
        _data_json_payload(
            distributions=[
                {
                    "@type": "dcat:Distribution",
                    "mediaType": "text/csv",
                    "downloadURL": "https://data.cms.gov/no-temporal.csv",
                },
                _csv_distribution(year=2023, url=BULK_CSV_URL_2023),
            ],
        ),
    )

    assert get_data_api_csv_url(BULK_DATASET_UUID) == BULK_CSV_URL_2023


# ---------------------------------------------------------------------------
# get_medicaid_dataset_csv_url — data.medicaid.gov metastore CSV resolution
# ---------------------------------------------------------------------------


def _medicaid_metastore_payload(*, download_url: str | None = MEDICAID_SDUD_CSV_URL) -> dict[str, object]:
    """Return a medicaid metastore record whose first distribution carries `download_url`."""
    distribution: dict[str, object] = {
        "@type": "dcat:Distribution",
        "format": "csv",
    }
    if download_url is not None:
        distribution["downloadURL"] = download_url
    return {
        "@type": "dcat:Dataset",
        "identifier": MEDICAID_SDUD_UUID,
        "title": "State Drug Utilization Data 2023",
        "distribution": [distribution],
    }


@respx.mock
def test_get_medicaid_dataset_csv_url_returns_first_distribution_url() -> None:
    """The first distribution's `downloadURL` is returned verbatim."""
    respx.get(f"{MEDICAID_BASE_URL}{MEDICAID_METASTORE_PATH}").respond(
        json=_medicaid_metastore_payload(),
    )

    assert get_dkan_dataset_csv_url(MEDICAID_SDUD_UUID, base_url=MEDICAID_BASE_URL) == MEDICAID_SDUD_CSV_URL


@respx.mock
def test_get_medicaid_dataset_csv_url_skips_distributions_without_download_url() -> None:
    """A leading distribution missing `downloadURL` is skipped, not raised on."""
    respx.get(f"{MEDICAID_BASE_URL}{MEDICAID_METASTORE_PATH}").respond(
        json={
            "@type": "dcat:Dataset",
            "identifier": MEDICAID_SDUD_UUID,
            "distribution": [
                {"@type": "dcat:Distribution", "format": "csv"},
                {"@type": "dcat:Distribution", "downloadURL": MEDICAID_SDUD_CSV_URL},
            ],
        },
    )

    assert get_dkan_dataset_csv_url(MEDICAID_SDUD_UUID, base_url=MEDICAID_BASE_URL) == MEDICAID_SDUD_CSV_URL


@respx.mock
def test_get_medicaid_dataset_csv_url_raises_when_no_download_url() -> None:
    """Every distribution lacking `downloadURL` is a `KeyError`, not a silent fallback."""
    respx.get(f"{MEDICAID_BASE_URL}{MEDICAID_METASTORE_PATH}").respond(
        json=_medicaid_metastore_payload(download_url=None),
    )

    with pytest.raises(KeyError, match="downloadURL"):
        get_dkan_dataset_csv_url(MEDICAID_SDUD_UUID, base_url=MEDICAID_BASE_URL)


@respx.mock
def test_get_medicaid_dataset_csv_url_rejects_non_object_payload() -> None:
    """A top-level array metastore response is malformed — surface loudly."""
    respx.get(f"{MEDICAID_BASE_URL}{MEDICAID_METASTORE_PATH}").respond(json=["unexpected"])

    with pytest.raises(TypeError, match="DKAN metastore"):
        get_dkan_dataset_csv_url(MEDICAID_SDUD_UUID, base_url=MEDICAID_BASE_URL)


@respx.mock
def test_get_medicaid_dataset_csv_url_rejects_non_list_distribution() -> None:
    """`distribution` must be a list — anything else is malformed."""
    respx.get(f"{MEDICAID_BASE_URL}{MEDICAID_METASTORE_PATH}").respond(
        json={"@type": "dcat:Dataset", "distribution": {"oops": "object"}},
    )

    with pytest.raises(TypeError, match="distribution"):
        get_dkan_dataset_csv_url(MEDICAID_SDUD_UUID, base_url=MEDICAID_BASE_URL)


# ---------------------------------------------------------------------------
# get_dkan_dataset_csv_url — openpaymentsdata.cms.gov via base_url override
# ---------------------------------------------------------------------------


def _open_payments_metastore_payload(*, download_url: str | None = OPEN_PAYMENTS_OWNERSHIP_CSV_URL) -> dict[str, object]:
    """Return an Open Payments metastore record with one CSV distribution."""
    distribution: dict[str, object] = {"@type": "dcat:Distribution", "format": "csv"}
    if download_url is not None:
        distribution["downloadURL"] = download_url
    return {
        "@type": "dcat:Dataset",
        "identifier": OPEN_PAYMENTS_OWNERSHIP_UUID,
        "title": "Ownership Payment Data - Detailed Dataset 2024 Reporting Year",
        "distribution": [distribution],
    }


@respx.mock
def test_get_dkan_dataset_csv_url_routes_open_payments_host() -> None:
    """``base_url=OPEN_PAYMENTS_BASE_URL`` hits openpaymentsdata.cms.gov, not data.medicaid.gov.

    This is the load-bearing test for the host-parameterization refactor:
    without it, the function would silently fall back to a single hard-coded
    host and Open Payments calls would 404 against the Medicaid metastore.
    """
    op_route = respx.get(f"{OPEN_PAYMENTS_BASE_URL}{OPEN_PAYMENTS_METASTORE_PATH}").respond(
        json=_open_payments_metastore_payload(),
    )
    medicaid_route = respx.get(f"{MEDICAID_BASE_URL}{OPEN_PAYMENTS_METASTORE_PATH}").respond(
        json=_open_payments_metastore_payload(download_url="https://wrong.example/should-not-be-hit.csv"),
    )

    url = get_dkan_dataset_csv_url(OPEN_PAYMENTS_OWNERSHIP_UUID, base_url=OPEN_PAYMENTS_BASE_URL)

    assert url == OPEN_PAYMENTS_OWNERSHIP_CSV_URL
    assert op_route.call_count == 1
    assert medicaid_route.call_count == 0


@respx.mock
def test_get_dkan_dataset_csv_url_open_payments_raises_when_no_download_url() -> None:
    """An Open Payments record with no downloadURL surfaces as a `KeyError`."""
    respx.get(f"{OPEN_PAYMENTS_BASE_URL}{OPEN_PAYMENTS_METASTORE_PATH}").respond(
        json=_open_payments_metastore_payload(download_url=None),
    )

    with pytest.raises(KeyError, match="downloadURL"):
        get_dkan_dataset_csv_url(OPEN_PAYMENTS_OWNERSHIP_UUID, base_url=OPEN_PAYMENTS_BASE_URL)
