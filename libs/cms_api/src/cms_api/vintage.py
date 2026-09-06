"""Dataset-vintage metadata capture.

Every CMS dataset the pipeline extracts is a point-in-time snapshot: the
publisher refreshes the file in place and the download URL keeps serving
"latest". This module fetches the publisher-side metadata that identifies
*which* snapshot an extraction landed — the DCAT ``modified`` / ``issued``
/ ``released`` dates and the ``temporal`` coverage range — so the
warehouse can expose an ``as_of`` date on snapshot-style marts.

Payloads here are tiny (one metastore record or the DCAT catalog), so a
vintage fetch is cheap relative to the extract it describes and safe to
re-run standalone (e.g. to backfill sidecars for already-landed data).

Source families without machine-readable snapshot metadata
(``healthcare_gov`` static content, ``socrata``) fall back to
:func:`local_vintage`, which records only the capture timestamp.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import TYPE_CHECKING, NamedTuple

from ._http import build_client, request_json
from .dkan import (
    _BARE_METASTORE_PATH_TEMPLATE,
    _CSV_MEDIA_TYPE,
    _DATA_JSON_PATH,
    _METASTORE_PATH_TEMPLATE,
    HEALTHCARE_GOV_DKAN_BASE_URL,
    MEDICAID_BASE_URL,
    OPEN_PAYMENTS_BASE_URL,
    PROVIDER_DATA_BASE_URL,
    _distribution_year,
    _find_dataset,
)
from pydantic import BaseModel, ConfigDict


if TYPE_CHECKING:
    from collections.abc import Callable

    from ._types import JsonObject, JsonValue
    from .registry import DatasetSpec


_ISO_DATE_LEN = 10  # "YYYY-MM-DD"


class DatasetVintage(BaseModel):
    """Vintage metadata for one extracted dataset snapshot.

    All dates come from the publisher's metadata record; any of them can
    be ``None`` when the publisher doesn't expose that field.
    ``captured_at`` is always set — it records when this vintage record
    was captured (extraction time for live runs, backfill time for
    sidecars regenerated after the fact).
    """

    model_config = ConfigDict(extra="forbid")

    dataset_key: str
    source_family: str
    dataset_id: str | None = None
    modified: date | None = None
    issued: date | None = None
    released: date | None = None
    temporal_start: date | None = None
    temporal_end: date | None = None
    captured_at: datetime


class _UpstreamDates(NamedTuple):
    """The publisher-side date fields of a vintage, before assembly."""

    modified: date | None = None
    issued: date | None = None
    released: date | None = None
    temporal_start: date | None = None
    temporal_end: date | None = None


def _coerce_date(value: JsonValue) -> date | None:
    """Parse the date prefix of a DCAT date-ish string, or ``None``.

    CMS publishes both bare dates (``"2026-07-22"``) and full timestamps
    (``"2026-07-13T15:43:41+00:00"``, seen on data.medicaid.gov); only
    the date part matters for vintage identity, so the prefix is parsed
    and the rest discarded. Unparseable values become ``None`` rather
    than failing the extraction they ride along with.
    """
    if not isinstance(value, str) or len(value) < _ISO_DATE_LEN:
        return None
    try:
        return date.fromisoformat(value[:_ISO_DATE_LEN])
    except ValueError:
        return None


def _parse_temporal(value: JsonValue) -> tuple[date | None, date | None]:
    """Split a DCAT ``temporal`` range (``"2024-01-01/2024-12-31"``) into dates."""
    if not isinstance(value, str) or "/" not in value:
        return None, None
    start_raw, _, end_raw = value.partition("/")
    return _coerce_date(start_raw), _coerce_date(end_raw)


def _require_dataset_id(spec: DatasetSpec) -> str:
    """Narrow ``spec.dataset_id`` to ``str``; the registry validator guarantees it."""
    if spec.dataset_id is None:
        msg = f"{spec.source} dataset {spec.key!r} is missing `dataset_id`"
        raise RuntimeError(msg)
    return spec.dataset_id


def _metastore_dates(*, base_url: str, path: str, dataset_id: str) -> _UpstreamDates:
    """Read the DCAT date fields off a DKAN metastore record."""
    with build_client(base_url=base_url) as client:
        payload = request_json(client, "GET", path)
    if not isinstance(payload, dict):
        msg = f"expected metastore record for {dataset_id!r} to be an object, got {type(payload).__name__}"
        raise TypeError(msg)
    temporal_start, temporal_end = _parse_temporal(payload.get("temporal"))
    return _UpstreamDates(
        modified=_coerce_date(payload.get("modified")),
        issued=_coerce_date(payload.get("issued")),
        released=_coerce_date(payload.get("released")),
        temporal_start=temporal_start,
        temporal_end=temporal_end,
    )


def _provider_data_dates(spec: DatasetSpec) -> _UpstreamDates:
    """Vintage dates for a Provider Data Catalog (Care Compare) dataset."""
    dataset_id = _require_dataset_id(spec)
    return _metastore_dates(
        base_url=PROVIDER_DATA_BASE_URL,
        path=_METASTORE_PATH_TEMPLATE.format(dataset_id=dataset_id),
        dataset_id=dataset_id,
    )


def _bare_metastore_dates(spec: DatasetSpec, *, base_url: str) -> _UpstreamDates:
    """Vintage dates for a bare-metastore DKAN dataset (``/api/1/`` root)."""
    dataset_id = _require_dataset_id(spec)
    return _metastore_dates(
        base_url=base_url,
        path=_BARE_METASTORE_PATH_TEMPLATE.format(dataset_id=dataset_id),
        dataset_id=dataset_id,
    )


def _medicaid_dates(spec: DatasetSpec) -> _UpstreamDates:
    """Vintage dates for a data.medicaid.gov dataset."""
    return _bare_metastore_dates(spec, base_url=MEDICAID_BASE_URL)


def _open_payments_dates(spec: DatasetSpec) -> _UpstreamDates:
    """Vintage dates for an openpaymentsdata.cms.gov dataset."""
    return _bare_metastore_dates(spec, base_url=OPEN_PAYMENTS_BASE_URL)


def _healthcare_gov_zip_dates(spec: DatasetSpec) -> _UpstreamDates:
    """Vintage dates for a data.healthcare.gov QHP Landscape dataset."""
    return _bare_metastore_dates(spec, base_url=HEALTHCARE_GOV_DKAN_BASE_URL)


def _select_csv_distribution(dataset: JsonObject, *, year: int | None) -> JsonObject | None:
    """Return the CSV distribution for ``year`` (or the latest year).

    Mirrors the selection in :func:`cms_api.dkan.get_data_api_csv_url` so
    the vintage describes the same distribution the bulk-CSV asset
    downloads. Returns ``None`` when no CSV distribution matches; the
    caller falls back to dataset-level metadata.
    """
    distributions: JsonValue = dataset.get("distribution", [])
    if not isinstance(distributions, list):
        return None
    by_year: dict[int, JsonObject] = {}
    for entry in distributions:
        if not isinstance(entry, dict) or entry.get("mediaType") != _CSV_MEDIA_TYPE:
            continue
        entry_year = _distribution_year(entry)
        if entry_year is None:
            continue
        by_year[entry_year] = entry
    if not by_year:
        return None
    if year is None:
        return by_year[max(by_year)]
    return by_year.get(year)


def _data_api_dates(spec: DatasetSpec) -> _UpstreamDates:
    """Vintage dates for a CMS data-api/v1 dataset from the DCAT catalog.

    ``modified`` and ``temporal`` prefer the selected year's CSV
    distribution (per-year files carry their own dates) and fall back to
    the dataset-level record; ``issued``/``released`` only exist at the
    dataset level.
    """
    dataset_id = _require_dataset_id(spec)
    with build_client(base_url=PROVIDER_DATA_BASE_URL) as client:
        catalog: JsonValue = request_json(client, "GET", _DATA_JSON_PATH)
    dataset = _find_dataset(catalog, dataset_id)
    distribution = _select_csv_distribution(dataset, year=spec.year)
    modified = None
    temporal: JsonValue = None
    if distribution is not None:
        modified = _coerce_date(distribution.get("modified"))
        temporal = distribution.get("temporal")
    if modified is None:
        modified = _coerce_date(dataset.get("modified"))
    if temporal is None:
        temporal = dataset.get("temporal")
    temporal_start, temporal_end = _parse_temporal(temporal)
    return _UpstreamDates(
        modified=modified,
        issued=_coerce_date(dataset.get("issued")),
        released=_coerce_date(dataset.get("released")),
        temporal_start=temporal_start,
        temporal_end=temporal_end,
    )


# Sources absent here fall back to `local_vintage` (capture time only):
# healthcare.gov static content publishes no snapshot metadata at all,
# and no live socrata registry row exists today. TODO: read
# `rowsUpdatedAt` from Socrata's `/api/views/{id}.json` if one ever
# returns — there's currently no payload shape to test against.
_UPSTREAM_FETCHERS: dict[str, Callable[[DatasetSpec], _UpstreamDates]] = {
    "dkan_provider_data": _provider_data_dates,
    "dkan_data_api_bulk": _data_api_dates,
    "dkan_medicaid_bulk": _medicaid_dates,
    "dkan_open_payments_bulk": _open_payments_dates,
    "dkan_healthcare_gov_zip": _healthcare_gov_zip_dates,
}


def local_vintage(dataset_key: str, source_family: str, *, dataset_id: str | None = None) -> DatasetVintage:
    """Build a vintage carrying only the capture timestamp.

    For extracts whose upstream publishes no snapshot metadata (e.g. the
    NPPES registry sweep, healthcare.gov static content), the capture
    time is the best available vintage proxy.
    """
    return DatasetVintage(
        dataset_key=dataset_key,
        source_family=source_family,
        dataset_id=dataset_id,
        captured_at=datetime.now(tz=UTC),
    )


def fetch_dataset_vintage(spec: DatasetSpec) -> DatasetVintage:
    """Fetch the current vintage metadata for a registry dataset.

    Dispatches on ``spec.source`` to the matching publisher-metadata
    fetcher; sources without one get a :func:`local_vintage`. Network
    errors propagate — a vintage that can't be fetched should fail the
    materialization it describes rather than silently landing stale
    metadata next to fresh data.
    """
    fetch = _UPSTREAM_FETCHERS.get(spec.source)
    if fetch is None:
        return local_vintage(spec.key, spec.source, dataset_id=spec.dataset_id)
    dates = fetch(spec)
    return DatasetVintage(
        dataset_key=spec.key,
        source_family=spec.source,
        dataset_id=spec.dataset_id,
        modified=dates.modified,
        issued=dates.issued,
        released=dates.released,
        temporal_start=dates.temporal_start,
        temporal_end=dates.temporal_end,
        captured_at=datetime.now(tz=UTC),
    )
