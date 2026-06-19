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

# Bulk CSV (`/data.json`)

The provider-summary-by-type-of-service datasets (Medicare Physician,
Part D Prescribers, Inpatient/Outpatient Hospitals) live on a *second*
DKAN deployment at ``data.cms.gov/data-api/v1/`` whose per-dataset
endpoint is currently 404. The reliable way to discover their per-year
CSV download URLs is the DCAT catalog at ``/data.json``; that's what
``get_data_api_csv_url`` resolves against. Each yearly distribution
exposes a ``downloadURL`` we can hand straight to DuckDB.

# Bare-metastore bulk CSV (Medicaid + Open Payments)

``data.medicaid.gov`` and ``openpaymentsdata.cms.gov`` run their own
DKAN deployments rooted at ``/api/1/`` (no ``/provider-data`` prefix).
For these we don't need ``/data.json`` discovery: each dataset's
metastore record already contains a single CSV distribution with a
direct ``downloadURL``, and CMS partitions by year at the dataset-UUID
level (one UUID per program year). ``get_dkan_dataset_csv_url`` reads
that downloadURL straight off the metastore for either host.

# Bare-metastore bulk ZIP (QHP Landscape on healthcare.gov)

``data.healthcare.gov`` is another bare-metastore DKAN at ``/api/1/``,
but the QHP Landscape PUFs distribute as ZIP-bundled XLSX rather than
direct CSV. ``get_dkan_dataset_zip_url`` resolves the ZIP downloadURL
from the same metastore shape; the extraction-to-Parquet step lives in
the Dagster asset because it requires a temp dir and DuckDB's excel
extension, not anything in this client.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from ._http import build_client, request_json


if TYPE_CHECKING:
    from collections.abc import Iterator

    from ._types import JsonObject, JsonValue
    import httpx


PROVIDER_DATA_BASE_URL = "https://data.cms.gov"
MEDICAID_BASE_URL = "https://data.medicaid.gov"
OPEN_PAYMENTS_BASE_URL = "https://openpaymentsdata.cms.gov"
HEALTHCARE_GOV_DKAN_BASE_URL = "https://data.healthcare.gov"
_METASTORE_PATH_TEMPLATE = "/provider-data/api/1/metastore/schemas/dataset/items/{dataset_id}"
_DATASTORE_PATH_TEMPLATE = "/provider-data/api/1/datastore/query/{distribution_id}"
_BARE_METASTORE_PATH_TEMPLATE = "/api/1/metastore/schemas/dataset/items/{dataset_id}"
_DATA_JSON_PATH = "/data.json"
_CSV_MEDIA_TYPE = "text/csv"
_DATASET_ID_URL_TEMPLATE = "/data-api/v1/dataset/{dataset_id}"
_YEAR_PREFIX_LEN = 4  # data.json `temporal` values start with a 4-digit year.
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


def _distribution_year(distribution: JsonObject) -> int | None:
    """Return the start-year of a distribution's ``temporal`` field, or None.

    CSV distributions in ``data.json`` annotate their coverage as
    ``YYYY-01-01/YYYY-12-31``; the start year is the data year we use
    to pick "latest" or to satisfy an explicit ``year=`` request.
    Distributions without a parseable temporal range are ignored by the
    selector (returned as ``None``).
    """
    temporal: JsonValue = distribution.get("temporal")
    if not isinstance(temporal, str) or len(temporal) < _YEAR_PREFIX_LEN:
        return None
    candidate = temporal[:_YEAR_PREFIX_LEN]
    if not candidate.isdigit():
        return None
    return int(candidate)


def _iter_csv_distributions(dataset: JsonObject) -> Iterator[tuple[int, str]]:
    """Yield ``(year, downloadURL)`` for each CSV distribution on ``dataset``.

    Non-CSV distributions, distributions without a string ``downloadURL``,
    and distributions whose ``temporal`` field isn't a recognisable year
    range are skipped.
    """
    distributions: JsonValue = dataset.get("distribution", [])
    if not isinstance(distributions, list):
        return
    for entry in distributions:
        if not isinstance(entry, dict):
            continue
        if entry.get("mediaType") != _CSV_MEDIA_TYPE:
            continue
        url: JsonValue = entry.get("downloadURL")
        if not isinstance(url, str) or not url:
            continue
        year = _distribution_year(entry)
        if year is None:
            continue
        yield year, url


def _find_dataset(catalog: JsonValue, dataset_id: str) -> JsonObject:
    """Return the catalog entry whose ``identifier`` carries ``dataset_id``.

    The DCAT catalog stores ``identifier`` as a full URL such as
    ``https://data.cms.gov/data-api/v1/dataset/<uuid>/data-viewer``; we
    match on the ``/dataset/<uuid>`` segment so callers can pass the bare
    UUID. Missing-dataset failures are surfaced as ``KeyError`` so they
    don't look like transport errors at the call site.
    """
    if not isinstance(catalog, dict):
        msg = f"expected data.json payload to be an object, got {type(catalog).__name__}"
        raise TypeError(msg)
    datasets: JsonValue = catalog.get("dataset", [])
    if not isinstance(datasets, list):
        msg = f"expected data.json `dataset` to be a list, got {type(datasets).__name__}"
        raise TypeError(msg)
    needle = _DATASET_ID_URL_TEMPLATE.format(dataset_id=dataset_id)
    for entry in datasets:
        if not isinstance(entry, dict):
            continue
        identifier: JsonValue = entry.get("identifier")
        if isinstance(identifier, str) and needle in identifier:
            return entry
    msg = f"no dataset in data.json with identifier matching {dataset_id!r}"
    raise KeyError(msg)


def get_data_api_csv_url(dataset_id: str, *, year: int | None = None) -> str:
    """Return the CSV ``downloadURL`` for a CMS data-api/v1 dataset.

    Looks the dataset up in the DCAT catalog at
    ``https://data.cms.gov/data.json``, filters to ``text/csv``
    distributions, and returns either the requested ``year``'s URL or
    the most recent year available.

    Args:
        dataset_id: Bare dataset UUID (e.g.
            ``"8889d81e-2ee7-448f-8713-f071038289b5"`` for Medicare
            Physician & Other Practitioners — by Provider).
        year: Optional 4-digit data year. When ``None``, the highest
            available year is returned.

    Raises:
        KeyError: The dataset is not in the catalog, or has no CSV
            distribution for the requested year.

    """
    with build_client(base_url=PROVIDER_DATA_BASE_URL) as client:
        catalog: JsonValue = request_json(client, "GET", _DATA_JSON_PATH)
    dataset = _find_dataset(catalog, dataset_id)
    by_year = dict(_iter_csv_distributions(dataset))
    if not by_year:
        msg = f"dataset {dataset_id!r} has no CSV distribution in data.json"
        raise KeyError(msg)
    if year is None:
        return by_year[max(by_year)]
    if year not in by_year:
        available = sorted(by_year)
        msg = f"dataset {dataset_id!r} has no CSV distribution for year {year}; available: {available}"
        raise KeyError(msg)
    return by_year[year]


def get_dkan_dataset_csv_url(dataset_id: str, *, base_url: str) -> str:
    """Return the CSV ``downloadURL`` for a bare-metastore DKAN dataset.

    Used for DKAN deployments whose metastore is rooted at ``/api/1/``
    (no ``/provider-data`` prefix) and whose datasets expose a single
    direct CSV distribution per program year — currently
    ``data.medicaid.gov`` (SDUD, NADAC) and ``openpaymentsdata.cms.gov``
    (General/Research/Ownership Payments). Year partitioning is done at
    the dataset-UUID level by CMS, so there's no year selector here.

    Args:
        dataset_id: Dataset UUID (e.g.
            ``"d890d3a9-6b00-43fd-8b31-fcba4c8e2909"`` for State Drug
            Utilization Data 2023, or
            ``"9ac4f7f8-b6e4-4d80-8410-4aba7e71dd02"`` for 2024 Open
            Payments Ownership).
        base_url: The DKAN host root, e.g. ``MEDICAID_BASE_URL`` or
            ``OPEN_PAYMENTS_BASE_URL``.

    Raises:
        KeyError: The metastore record has no distribution carrying a
            ``downloadURL`` string.
        TypeError: The metastore payload is shaped unexpectedly.

    """
    path = _BARE_METASTORE_PATH_TEMPLATE.format(dataset_id=dataset_id)
    with build_client(base_url=base_url) as client:
        payload: JsonValue = request_json(client, "GET", path)
    if not isinstance(payload, dict):
        msg = f"expected DKAN metastore payload to be an object, got {type(payload).__name__}"
        raise TypeError(msg)
    distributions: JsonValue = payload.get("distribution", [])
    if not isinstance(distributions, list):
        msg = f"expected `distribution` to be a list, got {type(distributions).__name__}"
        raise TypeError(msg)
    for entry in distributions:
        if not isinstance(entry, dict):
            continue
        url: JsonValue = entry.get("downloadURL")
        if isinstance(url, str) and url:
            return url
    msg = f"DKAN dataset {dataset_id!r} at {base_url!r} has no distribution with a downloadURL"
    raise KeyError(msg)


def get_dkan_dataset_zip_url(dataset_id: str, *, base_url: str) -> str:
    """Return the ZIP ``downloadURL`` for a bare-metastore DKAN dataset.

    Used for ``data.healthcare.gov`` QHP Landscape PUFs, which package the
    annual plan landscape spreadsheet as ZIP-bundled XLSX rather than the
    direct CSV pattern used by Medicaid/Open Payments. The metastore shape
    is identical; only the format filter differs, so we don't reuse
    ``get_dkan_dataset_csv_url`` — that one returns the first distribution
    indiscriminately and would happily hand back a non-ZIP if the dataset
    grew a second distribution down the road.

    Args:
        dataset_id: Dataset UUID (e.g.
            ``"6fe7fb77-7291-4104-952f-7c7e2c5d0c45"`` for QHP Landscape
            PY2026 Individual Medical).
        base_url: The DKAN host root, e.g. ``HEALTHCARE_GOV_DKAN_BASE_URL``.

    Raises:
        KeyError: No ZIP-format distribution carrying a ``downloadURL``
            was found on the metastore record.
        TypeError: The metastore payload is shaped unexpectedly.

    """
    path = _BARE_METASTORE_PATH_TEMPLATE.format(dataset_id=dataset_id)
    with build_client(base_url=base_url) as client:
        payload: JsonValue = request_json(client, "GET", path)
    if not isinstance(payload, dict):
        msg = f"expected DKAN metastore payload to be an object, got {type(payload).__name__}"
        raise TypeError(msg)
    distributions: JsonValue = payload.get("distribution", [])
    if not isinstance(distributions, list):
        msg = f"expected `distribution` to be a list, got {type(distributions).__name__}"
        raise TypeError(msg)
    for entry in distributions:
        if not isinstance(entry, dict):
            continue
        if not _is_zip_distribution(entry):
            continue
        url: JsonValue = entry.get("downloadURL")
        if isinstance(url, str) and url:
            return url
    msg = f"DKAN dataset {dataset_id!r} at {base_url!r} has no ZIP distribution with a downloadURL"
    raise KeyError(msg)


def _is_zip_distribution(entry: JsonObject) -> bool:
    """Return True if ``entry`` looks like a ZIP-format DCAT distribution.

    DKAN's metastore exposes both a ``format`` (`"zip"`) and a ``mediaType``
    (`"application/zip"`); either is sufficient. We tolerate case differences
    in either field — DKAN has shipped both lower-case and title-case
    formats in the wild.
    """
    fmt: JsonValue = entry.get("format")
    if isinstance(fmt, str) and fmt.lower() == "zip":
        return True
    media: JsonValue = entry.get("mediaType")
    return isinstance(media, str) and "zip" in media.lower()
