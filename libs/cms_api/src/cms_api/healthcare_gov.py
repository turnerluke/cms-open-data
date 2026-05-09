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
"""

from __future__ import annotations

from ._http import build_client, request_json
from pydantic import BaseModel, ConfigDict


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


def get_glossary() -> list[GlossaryTerm]:
    """Return every term in the Healthcare.gov glossary."""
    with build_client(base_url=HEALTHCARE_GOV_BASE_URL) as client:
        payload = request_json(client, "GET", GLOSSARY_PATH)
    return [GlossaryTerm.model_validate(item) for item in _extract_list(payload, key="glossary")]


def get_articles() -> list[Article]:
    """Return every Healthcare.gov article record."""
    with build_client(base_url=HEALTHCARE_GOV_BASE_URL) as client:
        payload = request_json(client, "GET", ARTICLES_PATH)
    return [Article.model_validate(item) for item in _extract_list(payload, key="articles")]


def _extract_list(payload: object, *, key: str) -> list[dict[str, object]]:
    """Pull a list out of a Healthcare.gov payload.

    Healthcare.gov's content endpoints sometimes return a bare JSON array and
    sometimes wrap it in a top-level object keyed by the resource name; this
    accepts either shape.
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
