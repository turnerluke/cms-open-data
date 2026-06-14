"""Tests for the DKAN Provider Data Catalog client."""

from cms_api.dkan import PROVIDER_DATA_BASE_URL, iter_provider_data_catalog
import httpx
import respx

import pytest


DATASET_ID = "xubh-q36u"  # Hospital General Information
DISTRIBUTION_ID = "11111111-2222-3333-4444-555555555555"
METASTORE_PATH = f"/provider-data/api/1/metastore/schemas/dataset/items/{DATASET_ID}"
DATASTORE_PATH = f"/provider-data/api/1/datastore/query/{DISTRIBUTION_ID}"


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
