"""Healthcare.gov content API client.

Healthcare.gov publishes its site content (glossary terms, articles) under
``https://www.healthcare.gov/api/...``. These are static JSON snapshots of
the public site and need no authentication.

Note: the Marketplace **plan-finder** API (plans for sale, premiums, network
data) is a separate, gated service and is **not** covered here. When that
data is needed, it'll get its own module with its own auth.

# Design choices
- **Single-shot endpoints, no pagination.** The content endpoints return the
  full corpus in one response (the dataset is small). We return a `list` so
  callers can re-iterate without re-fetching — a generator would force them
  to materialise it themselves anyway.
- **Shape-tolerant.** Healthcare.gov sometimes returns a bare JSON array
  (`[...]`) and sometimes a wrapped object (`{"glossary": [...]}`). The
  shared `_extract_list` accepts either, using a path-derived envelope key
  so the registry generator can call `get_static_json(path)` uniformly.
"""

from __future__ import annotations

from pathlib import PurePosixPath
from typing import TYPE_CHECKING

from ._http import build_client, request_json
from pydantic import BaseModel, ConfigDict


if TYPE_CHECKING:
    from ._types import JsonObject, JsonValue


HEALTHCARE_GOV_BASE_URL = "https://www.healthcare.gov"
GLOSSARY_PATH = "/api/glossary.json"
ARTICLES_PATH = "/api/articles.json"


class GlossaryTerm(BaseModel):
    """A single Healthcare.gov glossary entry."""

    model_config = ConfigDict(extra="allow")

    title: str | None = None
    slug: str | None = None
    content: str | None = None


class Article(BaseModel):
    """A Healthcare.gov article record."""

    model_config = ConfigDict(extra="allow")

    title: str | None = None
    slug: str | None = None
    url: str | None = None
    content: str | None = None
    date: str | None = None


def get_static_json(path: str) -> list[JsonObject]:
    """GET a Healthcare.gov static JSON endpoint and return its records.

    Healthcare.gov content endpoints return either a bare JSON array or
    an object wrapping the array under a key derived from the resource
    name (e.g. ``/api/glossary.json`` -> ``{"glossary": [...]}``); both
    shapes are accepted. The envelope key is the path's basename without
    extension, which covers every known endpoint without hardcoding.
    """
    with build_client(base_url=HEALTHCARE_GOV_BASE_URL) as client:
        payload = request_json(client, "GET", path)
    return _extract_list(payload, key=PurePosixPath(path).stem)


def get_glossary() -> list[GlossaryTerm]:
    """Return every term in the Healthcare.gov glossary."""
    return [GlossaryTerm.model_validate(item) for item in get_static_json(GLOSSARY_PATH)]


def get_articles() -> list[Article]:
    """Return every Healthcare.gov article record."""
    return [Article.model_validate(item) for item in get_static_json(ARTICLES_PATH)]


def _extract_list(payload: JsonValue, *, key: str) -> list[JsonObject]:
    """Pull a list of JSON objects out of a Healthcare.gov payload.

    Healthcare.gov's content endpoints sometimes return a bare JSON array and
    sometimes wrap it in a top-level object keyed by the resource name; this
    accepts either shape. Non-object entries (rare, but observed) are
    silently dropped to keep one malformed row from breaking the whole pull.
    """
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        inner = payload.get(key, [])
        if isinstance(inner, list):
            return [item for item in inner if isinstance(item, dict)]
        msg = f"expected payload[{key!r}] to be a list, got {type(inner).__name__}"
        raise TypeError(msg)
    msg = f"expected JSON list or object, got {type(payload).__name__}"
    raise TypeError(msg)
