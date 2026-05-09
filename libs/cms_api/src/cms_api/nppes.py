"""NPPES NPI Registry client.

The NPI Registry exposes a single REST endpoint that powers both lookup-by-NPI
and full-text search. Pagination is via a ``skip`` query param; the API caps a
single response at 200 rows and a total skip of 1000 (so a search can surface
at most 1200 records — clients filtering further than that should narrow the
query, not paginate harder).

# Design choices
- **One Pydantic model per logical record (provider).** Subobjects (addresses,
  taxonomies, identifiers) are typed; ``extra='allow'`` keeps fields we don't
  declare reachable.
- **Pagination yields all reachable rows then stops cleanly at the API's hard
  cap.** The cap is a property of the endpoint, not a bug — surfacing it as a
  silent truncation matches the NPPES docs and lets callers compare
  ``result_count`` themselves if they care.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Literal


if TYPE_CHECKING:
    from collections.abc import Iterator

from ._http import build_client, request_json
from pydantic import BaseModel, ConfigDict, Field


NPPES_BASE_URL = "https://npiregistry.cms.hhs.gov"
NPPES_PATH = "/api/"
NPPES_API_VERSION = "2.1"

# NPPES caps: 200 rows per response, total skip 1000 → max 1200 reachable rows.
NPPES_MAX_PAGE_SIZE = 200
NPPES_MAX_SKIP = 1000


class NppesAddress(BaseModel):
    """An address attached to an NPPES record (mailing or location)."""

    model_config = ConfigDict(extra="allow")

    address_purpose: str | None = None
    address_type: str | None = None
    address_1: str | None = None
    address_2: str | None = None
    city: str | None = None
    state: str | None = None
    postal_code: str | None = None
    country_code: str | None = None
    telephone_number: str | None = None


class NppesTaxonomy(BaseModel):
    """A taxonomy (specialty) entry on an NPPES record."""

    model_config = ConfigDict(extra="allow")

    code: str | None = None
    desc: str | None = None
    primary: bool | None = None
    state: str | None = None
    license: str | None = None


class NppesBasic(BaseModel):
    """The ``basic`` block of an NPPES record (name, status, credentials, ...)."""

    model_config = ConfigDict(extra="allow")

    first_name: str | None = None
    last_name: str | None = None
    organization_name: str | None = None
    credential: str | None = None
    sole_proprietor: str | None = None
    gender: str | None = None
    enumeration_date: str | None = None
    last_updated: str | None = None
    status: str | None = None


class NppesProvider(BaseModel):
    """An NPPES provider record."""

    model_config = ConfigDict(extra="allow")

    number: str = Field(description="The 10-digit NPI.")
    enumeration_type: Literal["NPI-1", "NPI-2"] | None = None
    basic: NppesBasic | None = None
    addresses: list[NppesAddress] = Field(default_factory=list)
    taxonomies: list[NppesTaxonomy] = Field(default_factory=list)


def _base_query(version: str = NPPES_API_VERSION) -> dict[str, str]:
    """Return the always-present query params for an NPPES request."""
    return {"version": version}


def get_provider_by_npi(npi: str) -> NppesProvider | None:
    """Look up a single provider by NPI. Returns ``None`` if no record exists.

    NPPES returns ``result_count: 0`` rather than 404 for unknown NPIs, so the
    None case is part of the normal response.
    """
    if not npi.isdigit() or len(npi) != 10:  # noqa: PLR2004 -- 10 is the literal NPI length
        msg = f"NPI must be a 10-digit numeric string, got {npi!r}"
        raise ValueError(msg)

    params = {**_base_query(), "number": npi}
    with build_client(base_url=NPPES_BASE_URL) as client:
        payload = request_json(client, "GET", NPPES_PATH, params=params)
    results = _extract_results(payload)
    if not results:
        return None
    return NppesProvider.model_validate(results[0])


def search_providers(  # noqa: PLR0913 -- public API; explicit kwargs are clearer than a params object
    *,
    first_name: str | None = None,
    last_name: str | None = None,
    organization_name: str | None = None,
    state: str | None = None,
    postal_code: str | None = None,
    enumeration_type: Literal["NPI-1", "NPI-2"] | None = None,
    taxonomy_description: str | None = None,
    page_size: int = NPPES_MAX_PAGE_SIZE,
) -> Iterator[NppesProvider]:
    """Search the NPI Registry, yielding one provider per row.

    Pagination is internal: we walk ``skip`` up to NPPES's 1000-row cap and
    stop when a page comes back short. Callers wanting more than the API's
    1200-row reachable window must narrow the query.
    """
    if page_size <= 0 or page_size > NPPES_MAX_PAGE_SIZE:
        msg = f"page_size must be between 1 and {NPPES_MAX_PAGE_SIZE}, got {page_size}"
        raise ValueError(msg)

    optional_params: dict[str, str | None] = {
        "first_name": first_name,
        "last_name": last_name,
        "organization_name": organization_name,
        "state": state,
        "postal_code": postal_code,
        "enumeration_type": enumeration_type,
        "taxonomy_description": taxonomy_description,
    }
    base_params: dict[str, str] = {
        **_base_query(),
        "limit": str(page_size),
        **{k: v for k, v in optional_params.items() if v is not None},
    }

    skip = 0
    with build_client(base_url=NPPES_BASE_URL) as client:
        while True:
            params = {**base_params, "skip": str(skip)}
            payload = request_json(client, "GET", NPPES_PATH, params=params)
            results = _extract_results(payload)
            if not results:
                return
            for row in results:
                yield NppesProvider.model_validate(row)
            if len(results) < page_size:
                return
            skip += page_size
            if skip > NPPES_MAX_SKIP:
                return


def _extract_results(payload: Any) -> list[dict[str, Any]]:  # noqa: ANN401 -- API payload shape
    """Pull the ``results`` list out of an NPPES response payload."""
    if not isinstance(payload, dict):
        msg = f"expected JSON object from NPPES, got {type(payload).__name__}"
        raise TypeError(msg)
    results = payload.get("results", [])
    if not isinstance(results, list):
        msg = f"expected 'results' to be a list, got {type(results).__name__}"
        raise TypeError(msg)
    return results
