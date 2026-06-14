"""DKAN Provider Data Catalog client.

The CMS Provider Data Catalog (Care Compare datasets — hospitals, hospices,
home health, dialysis, …) is published on a DKAN deployment at
``https://data.cms.gov/provider-data/api/1/``. The schema is stable enough
that we use a single thin client and let the registry name datasets by
their canonical UUID, the same way the Socrata client uses the 4x4 ID.

# Why a separate client from `socrata`?

DKAN's datastore is a different backend with different pagination semantics:

- **Distribution indirection.** Each metastore record has one or more
  `distribution[]` entries; the actual queryable resource is identified by
  ``distribution[].identifier`` and CMS reissues this when the dataset is
  refreshed mid-year. Hardcoding ``/datastore/query/{id}/0`` works *most*
  of the time but returns 404 the day after a reissue. We resolve the
  current identifier from the metastore on every iteration.
- **`limit`/`offset` query params, not SoQL.** No `$select` / `$where`;
  filtering is a client-side concern.

We still reuse ``cms_api._http`` so retry/backoff/headers behave the same
across clients.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from ._http import build_client, request_json


if TYPE_CHECKING:
    from collections.abc import Iterator

    from ._types import JsonObject, JsonValue
    import httpx


PROVIDER_DATA_BASE_URL = "https://data.cms.gov"
_METASTORE_PATH_TEMPLATE = "/provider-data/api/1/metastore/schemas/dataset/items/{dataset_id}"
_DATASTORE_PATH_TEMPLATE = "/provider-data/api/1/datastore/query/{distribution_id}"
DEFAULT_BATCH_SIZE = 1000


def _resolve_distribution_id(client: httpx.Client, dataset_id: str) -> str:
    """Return the current ``distribution[0].identifier`` for ``dataset_id``.

    The Provider Data Catalog reissues datasets periodically; the datastore
    is keyed by distribution identifier rather than the stable dataset UUID,
    so we look up the live identifier before each iteration.

    DKAN only emits the distribution UUIDs when ``show-reference-ids`` is
    set; without it the metastore returns the de-referenced ``dcat:Distribution``
    fields (downloadURL, mediaType, …) but not the queryable identifier.
    """
    path = _METASTORE_PATH_TEMPLATE.format(dataset_id=dataset_id)
    payload = request_json(client, "GET", path, params={"show-reference-ids": ""})
    if not isinstance(payload, dict):
        msg = f"expected metastore payload to be an object, got {type(payload).__name__}"
        raise TypeError(msg)
    distributions: JsonValue = payload.get("distribution", [])
    if not isinstance(distributions, list) or not distributions:
        msg = f"metastore record for {dataset_id!r} has no distributions"
        raise ValueError(msg)
    first = distributions[0]
    if not isinstance(first, dict):
        msg = f"expected distribution[0] to be an object, got {type(first).__name__}"
        raise TypeError(msg)
    identifier: JsonValue = first.get("identifier")
    if not isinstance(identifier, str) or not identifier:
        msg = f"distribution[0].identifier missing or non-string for {dataset_id!r}"
        raise ValueError(msg)
    return identifier


def _validate_datastore_page(payload: JsonValue) -> list[JsonObject]:
    """Narrow a DKAN datastore page payload to a list of JSON objects."""
    if not isinstance(payload, dict):
        msg = f"expected datastore page to be a JSON object, got {type(payload).__name__}"
        raise TypeError(msg)
    results: JsonValue = payload.get("results", [])
    if not isinstance(results, list):
        msg = f"expected `results` to be a list, got {type(results).__name__}"
        raise TypeError(msg)
    rows: list[JsonObject] = []
    for row in results:
        if not isinstance(row, dict):
            msg = f"expected datastore row to be a JSON object, got {type(row).__name__}"
            raise TypeError(msg)
        rows.append(row)
    return rows


def iter_provider_data_catalog(
    dataset_id: str,
    *,
    batch_size: int = DEFAULT_BATCH_SIZE,
) -> Iterator[JsonObject]:
    """Yield every row of a Provider Data Catalog dataset, paginating with ``limit``/``offset``.

    Args:
        dataset_id: The dataset's stable metastore UUID (e.g. ``"xubh-q36u"``
            for Hospital General Information).
        batch_size: Page size. DKAN accepts large pages but 1,000 keeps
            memory and request size modest; same default as the Socrata
            client for consistency.

    Yields:
        One dict per row. Values are whatever DKAN returns (mostly strings).

    """
    with build_client(base_url=PROVIDER_DATA_BASE_URL) as client:
        distribution_id = _resolve_distribution_id(client, dataset_id)
        path = _DATASTORE_PATH_TEMPLATE.format(distribution_id=distribution_id)
        offset = 0
        while True:
            page_params = {"limit": str(batch_size), "offset": str(offset)}
            payload = request_json(client, "GET", path, params=page_params)
            rows = _validate_datastore_page(payload)
            if not rows:
                return
            yield from rows
            if len(rows) < batch_size:
                return
            offset += batch_size
