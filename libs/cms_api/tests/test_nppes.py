"""Tests for the NPPES client."""

from cms_api import JsonObject
from cms_api.nppes import NPPES_BASE_URL, NPPES_PATH, get_provider_by_npi, search_providers
import httpx
import respx

import pytest


NPPES_URL = f"{NPPES_BASE_URL}{NPPES_PATH}"


def _provider_payload(npi: str, last_name: str = "Doe") -> JsonObject:
    """Minimal NPPES result row."""
    return {
        "number": npi,
        "enumeration_type": "NPI-1",
        "basic": {"first_name": "Jane", "last_name": last_name, "status": "A"},
        "addresses": [
            {
                "address_purpose": "LOCATION",
                "address_1": "123 Main St",
                "city": "Springfield",
                "state": "IL",
                "postal_code": "62701",
            },
        ],
        "taxonomies": [{"code": "207Q00000X", "desc": "Family Medicine", "primary": True}],
    }


@respx.mock
def test_get_provider_by_npi_happy_path() -> None:
    """A 200 with one result returns the typed provider."""
    respx.get(NPPES_URL).respond(json={"result_count": 1, "results": [_provider_payload("1234567893")]})

    provider = get_provider_by_npi("1234567893")

    assert provider is not None
    assert provider.number == "1234567893"
    assert provider.basic is not None
    assert provider.basic.last_name == "Doe"
    assert provider.addresses[0].state == "IL"
    assert provider.taxonomies[0].code == "207Q00000X"


@respx.mock
def test_get_provider_by_npi_returns_none_when_not_found() -> None:
    """NPPES returns 200 + empty results for unknown NPIs; we map that to None."""
    respx.get(NPPES_URL).respond(json={"result_count": 0, "results": []})

    assert get_provider_by_npi("9999999999") is None


def test_get_provider_by_npi_validates_format() -> None:
    """Non-10-digit input fails fast without making a request."""
    with pytest.raises(ValueError, match="10-digit"):
        get_provider_by_npi("abc")
    with pytest.raises(ValueError, match="10-digit"):
        get_provider_by_npi("12345")


@respx.mock
def test_search_providers_paginates_with_skip() -> None:
    """A full page triggers another request with `skip` advanced by `page_size`."""
    page_a = {"results": [_provider_payload(f"100000000{i}") for i in range(2)]}
    page_b = {"results": [_provider_payload("1000000099")]}  # short → stop

    route = respx.get(NPPES_URL).mock(
        side_effect=[httpx.Response(200, json=page_a), httpx.Response(200, json=page_b)],
    )

    providers = list(search_providers(last_name="Doe", page_size=2))

    assert len(providers) == 3
    assert route.call_count == 2
    first_call_params = dict(route.calls[0].request.url.params)
    second_call_params = dict(route.calls[1].request.url.params)
    assert first_call_params["skip"] == "0"
    assert first_call_params["last_name"] == "Doe"
    assert first_call_params["limit"] == "2"
    assert second_call_params["skip"] == "2"


@respx.mock
def test_search_providers_stops_at_skip_cap() -> None:
    """We stop walking past the NPPES 1000-row skip cap even if pages keep coming."""
    full_page = {"results": [_provider_payload(f"10000000{i:02d}") for i in range(200)]}
    route = respx.get(NPPES_URL).mock(return_value=httpx.Response(200, json=full_page))

    providers = list(search_providers(last_name="Smith", page_size=200))

    # 6 pages of 200 rows = 1200 rows, then skip would be 1200 (>1000 cap) and we stop.
    assert len(providers) == 1200
    assert route.call_count == 6


@respx.mock
def test_search_providers_retries_on_transient_then_yields() -> None:
    """A 502 is retried, and the subsequent good page is yielded."""
    route = respx.get(NPPES_URL).mock(
        side_effect=[
            httpx.Response(502, text="bad gateway"),
            httpx.Response(200, json={"results": [_provider_payload("1234567893")]}),
        ],
    )

    providers = list(search_providers(last_name="Doe", page_size=10))

    assert len(providers) == 1
    assert route.call_count == 2


def test_search_providers_rejects_invalid_page_size() -> None:
    """Page size must be within NPPES's 1..200 window."""
    with pytest.raises(ValueError, match="page_size"):
        list(search_providers(page_size=0))
    with pytest.raises(ValueError, match="page_size"):
        list(search_providers(page_size=500))


@respx.mock
def test_search_providers_passes_all_filters() -> None:
    """All filter kwargs land on the request as query params."""
    route = respx.get(NPPES_URL).respond(json={"results": []})

    list(
        search_providers(
            first_name="Jane",
            last_name="Doe",
            organization_name="Acme Health",
            state="CA",
            postal_code="90210",
            enumeration_type="NPI-2",
            taxonomy_description="Family Medicine",
        ),
    )

    params = dict(route.calls.last.request.url.params)
    assert params["first_name"] == "Jane"
    assert params["last_name"] == "Doe"
    assert params["organization_name"] == "Acme Health"
    assert params["state"] == "CA"
    assert params["postal_code"] == "90210"
    assert params["enumeration_type"] == "NPI-2"
    assert params["taxonomy_description"] == "Family Medicine"
    assert params["version"] == "2.1"


@respx.mock
def test_get_provider_by_npi_rejects_non_object_payload() -> None:
    """A list payload from NPPES is a server bug; raise rather than silently empty."""
    respx.get(NPPES_URL).respond(json=[])

    with pytest.raises(TypeError, match="expected JSON object"):
        get_provider_by_npi("1234567893")


@respx.mock
def test_get_provider_by_npi_rejects_non_list_results() -> None:
    """`results` must be a list; anything else is malformed."""
    respx.get(NPPES_URL).respond(json={"results": {"oops": "object"}})

    with pytest.raises(TypeError, match="results"):
        get_provider_by_npi("1234567893")
