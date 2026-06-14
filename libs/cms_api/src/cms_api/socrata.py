"""Socrata client.

`data.cms.gov` and `data.medicaid.gov` both run on the Socrata Open Data API,
so a single client covers both — callers pick the domain.

# Design choices
- **Generators, not lists.** `iter_dataset` yields rows so callers can stream
  large datasets without materialising the full result set in memory.
- **No raw `httpx.Response` exposure.** Callers get parsed rows; if they need
  raw HTTP behaviour they can build their own client with ``build_client``.
- **No per-dataset wrappers.** Each dataset is one row in the registry
  (`cms_api.registry.load_registry`); the Dagster generator calls
  `iter_dataset(dataset_id, domain=...)` directly. Hand-written Pydantic
  classes per dataset proved low-value (Socrata schemas drift; we always
  fell back to `extra='allow'`) and made adding datasets expensive.
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING

from ._http import build_client, request_json


if TYPE_CHECKING:
    from collections.abc import Iterator, Mapping

    from ._types import JsonObject, JsonValue


CMS_DOMAIN = "data.cms.gov"
MEDICAID_DOMAIN = "data.medicaid.gov"
DEFAULT_BATCH_SIZE = 1000


def _socrata_path(dataset_id: str) -> str:
    """Return the Socrata resource path for ``dataset_id``."""
    return f"/resource/{dataset_id}.json"


def _resolve_app_token(app_token: str | None) -> str | None:
    """Resolve the Socrata app token, defaulting to the ``CMS_API_SOCRATA_APP_TOKEN`` env var."""
    if app_token is not None:
        return app_token
    return os.environ.get("CMS_API_SOCRATA_APP_TOKEN")


def _validate_socrata_page(page: JsonValue) -> list[JsonObject]:
    """Narrow a Socrata page payload to a list of JSON objects."""
    if not isinstance(page, list):
        msg = f"expected JSON array from Socrata, got {type(page).__name__}"
        raise TypeError(msg)
    rows: list[JsonObject] = []
    for row in page:
        if not isinstance(row, dict):
            msg = f"expected Socrata row to be a JSON object, got {type(row).__name__}"
            raise TypeError(msg)
        rows.append(row)
    return rows


def iter_dataset(  # noqa: PLR0913 -- public API; keyword-only args make explicit kwargs preferable to a params object
    dataset_id: str,
    *,
    domain: str = CMS_DOMAIN,
    select: str | None = None,
    where: str | None = None,
    order: str | None = None,
    extra_params: Mapping[str, str] | None = None,
    app_token: str | None = None,
    batch_size: int = DEFAULT_BATCH_SIZE,
) -> Iterator[JsonObject]:
    """Yield every row of a Socrata dataset, paginating with ``$limit``/``$offset``.

    Args:
        dataset_id: Socrata 4x4 ID, e.g. ``"mhdd-npjx"``.
        domain: Socrata host. Defaults to ``data.cms.gov``; pass
            ``data.medicaid.gov`` for Medicaid datasets.
        select: SoQL ``$select`` clause.
        where: SoQL ``$where`` clause.
        order: SoQL ``$order`` clause. Stable ordering is recommended for
            multi-page reads to avoid duplicates if the dataset is updated
            mid-iteration.
        extra_params: Additional SoQL params to pass through (e.g. ``$q``).
            Use sparingly — most filtering should go through ``where``.
        app_token: Socrata app token. Falls back to the
            ``CMS_API_SOCRATA_APP_TOKEN`` environment variable. Not strictly
            required but recommended to avoid throttle limits.
        batch_size: Page size. Socrata's max is 50,000; the default of 1,000
            keeps memory and request size modest.

    Yields:
        One dict per row. Values are whatever Socrata returns (mostly strings).

    """
    resolved_token = _resolve_app_token(app_token)
    headers: dict[str, str] | None = {"X-App-Token": resolved_token} if resolved_token else None
    base_url = f"https://{domain}"
    path = _socrata_path(dataset_id)

    base_params: dict[str, str] = {}
    if select is not None:
        base_params["$select"] = select
    if where is not None:
        base_params["$where"] = where
    if order is not None:
        base_params["$order"] = order
    if extra_params:
        base_params.update(extra_params)

    offset = 0
    with build_client(base_url=base_url, headers=headers) as client:
        while True:
            page_params = {**base_params, "$limit": str(batch_size), "$offset": str(offset)}
            page = request_json(client, "GET", path, params=page_params)
            rows = _validate_socrata_page(page)
            if not rows:
                return
            yield from rows
            if len(rows) < batch_size:
                return
            offset += batch_size
