"""Tests for the Socrata client."""

from cms_api.socrata import DATASET_PART_D_SPENDING_BY_DRUG, MEDICAID_DOMAIN, iter_dataset, iter_part_d_spending_by_drug
import httpx
import respx

import pytest


PART_D_PATH = f"/resource/{DATASET_PART_D_SPENDING_BY_DRUG}.json"
CMS_BASE = "https://data.cms.gov"
MEDICAID_BASE = f"https://{MEDICAID_DOMAIN}"


@respx.mock
def test_iter_part_d_spending_by_drug_happy_path() -> None:
    """A single page response yields one typed row per dict."""
    respx.get(f"{CMS_BASE}{PART_D_PATH}").respond(
        json=[
            {"brnd_name": "Drug A", "gnrc_name": "GenA", "mftr_name": "MfgA", "tot_spndng_2022": "1000"},
            {"brnd_name": "Drug B", "gnrc_name": "GenB", "mftr_name": "MfgB", "tot_spndng_2022": "2500"},
        ],
    )

    rows = list(iter_part_d_spending_by_drug())

    assert len(rows) == 2
    assert rows[0].brnd_name == "Drug A"
    assert rows[0].gnrc_name == "GenA"
    # Year-suffixed columns flow through as Pydantic extras.
    assert rows[0].model_dump()["tot_spndng_2022"] == "1000"


@respx.mock
def test_iter_dataset_paginates_until_short_page() -> None:
    """`iter_dataset` keeps paging while a full batch comes back, stops on a short one."""
    page_a = [{"id": str(i)} for i in range(2)]
    page_b = [{"id": "2"}]  # short page → loop exits

    route = respx.get(f"{CMS_BASE}{PART_D_PATH}").mock(
        side_effect=[
            httpx.Response(200, json=page_a),
            httpx.Response(200, json=page_b),
        ],
    )

    rows = list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, batch_size=2))

    assert [r["id"] for r in rows] == ["0", "1", "2"]
    assert route.call_count == 2
    assert dict(route.calls[0].request.url.params)["$offset"] == "0"
    assert dict(route.calls[1].request.url.params)["$offset"] == "2"


@respx.mock
def test_iter_dataset_stops_on_empty_page() -> None:
    """An empty array terminates pagination immediately."""
    route = respx.get(f"{CMS_BASE}{PART_D_PATH}").mock(
        side_effect=[
            httpx.Response(200, json=[{"id": "0"}, {"id": "1"}]),
            httpx.Response(200, json=[]),
        ],
    )

    rows = list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, batch_size=2))

    assert len(rows) == 2
    assert route.call_count == 2


@respx.mock
def test_iter_dataset_passes_soql_clauses_and_app_token() -> None:
    """`select`, `where`, `order`, and the app-token header all reach the request."""
    route = respx.get(f"{CMS_BASE}{PART_D_PATH}").respond(json=[])

    list(
        iter_dataset(
            DATASET_PART_D_SPENDING_BY_DRUG,
            select="brnd_name, mftr_name",
            where="mftr_name = 'Pfizer'",
            order="brnd_name",
            app_token="tok-123",
        ),
    )

    request = route.calls.last.request
    params = dict(request.url.params)
    assert params["$select"] == "brnd_name, mftr_name"
    assert params["$where"] == "mftr_name = 'Pfizer'"
    assert params["$order"] == "brnd_name"
    assert request.headers["X-App-Token"] == "tok-123"


@respx.mock
def test_iter_dataset_uses_medicaid_domain() -> None:
    """`domain=MEDICAID_DOMAIN` routes the request to data.medicaid.gov."""
    route = respx.get(f"{MEDICAID_BASE}{PART_D_PATH}").respond(json=[{"id": "x"}])

    rows = list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, domain=MEDICAID_DOMAIN, batch_size=10))

    assert rows == [{"id": "x"}]
    assert route.call_count == 1


@respx.mock
def test_iter_dataset_retries_on_5xx_then_succeeds() -> None:
    """Transient 503 is retried; the eventual 200 page is yielded."""
    route = respx.get(f"{CMS_BASE}{PART_D_PATH}").mock(
        side_effect=[
            httpx.Response(503, json={"error": "down"}),
            httpx.Response(200, json=[{"id": "0"}]),
        ],
    )

    rows = list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, batch_size=10))

    assert rows == [{"id": "0"}]
    assert route.call_count == 2


@respx.mock
def test_iter_dataset_retries_on_429() -> None:
    """HTTP 429 (Too Many Requests) is treated as transient."""
    route = respx.get(f"{CMS_BASE}{PART_D_PATH}").mock(
        side_effect=[
            httpx.Response(429),
            httpx.Response(200, json=[{"id": "0"}]),
        ],
    )

    rows = list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, batch_size=10))

    assert rows == [{"id": "0"}]
    assert route.call_count == 2


@respx.mock
def test_iter_dataset_does_not_retry_on_4xx() -> None:
    """A 400 surfaces immediately rather than burning retry budget."""
    route = respx.get(f"{CMS_BASE}{PART_D_PATH}").respond(400, json={"error": "bad query"})

    with pytest.raises(httpx.HTTPStatusError):
        list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, batch_size=10))

    assert route.call_count == 1


@respx.mock
def test_iter_dataset_rejects_non_array_payload() -> None:
    """Socrata always returns an array; anything else is a server bug worth raising on."""
    respx.get(f"{CMS_BASE}{PART_D_PATH}").respond(json={"unexpected": "object"})

    with pytest.raises(TypeError, match="expected JSON array"):
        list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, batch_size=10))


@respx.mock
def test_iter_dataset_rejects_non_object_row() -> None:
    """Socrata rows are JSON objects; a scalar row would mean the response is malformed."""
    respx.get(f"{CMS_BASE}{PART_D_PATH}").respond(json=["not-a-dict"])

    with pytest.raises(TypeError, match="expected Socrata row to be a JSON object"):
        list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG, batch_size=10))


@respx.mock
def test_iter_dataset_reads_app_token_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """The Socrata app token defaults to the env var when not passed in."""
    monkeypatch.setenv("CMS_API_SOCRATA_APP_TOKEN", "env-token")
    route = respx.get(f"{CMS_BASE}{PART_D_PATH}").respond(json=[])

    list(iter_dataset(DATASET_PART_D_SPENDING_BY_DRUG))

    assert route.calls.last.request.headers["X-App-Token"] == "env-token"
