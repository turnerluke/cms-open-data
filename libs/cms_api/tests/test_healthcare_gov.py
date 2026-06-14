"""Tests for the Healthcare.gov content client."""

from cms_api.healthcare_gov import (
    ARTICLES_PATH,
    GLOSSARY_PATH,
    HEALTHCARE_GOV_BASE_URL,
    get_articles,
    get_glossary,
    get_static_json,
)
import httpx
import respx

import pytest


GLOSSARY_URL = f"{HEALTHCARE_GOV_BASE_URL}{GLOSSARY_PATH}"
ARTICLES_URL = f"{HEALTHCARE_GOV_BASE_URL}{ARTICLES_PATH}"


@respx.mock
def test_get_glossary_happy_path_bare_array() -> None:
    """Healthcare.gov sometimes returns a bare JSON array; that's accepted."""
    respx.get(GLOSSARY_URL).respond(
        json=[
            {"title": "Premium", "slug": "premium", "content": "The amount you pay…"},
            {"title": "Deductible", "slug": "deductible", "content": "The amount…"},
        ],
    )

    terms = get_glossary()

    assert len(terms) == 2
    assert terms[0].title == "Premium"
    assert terms[1].slug == "deductible"


@respx.mock
def test_get_glossary_handles_wrapped_object() -> None:
    """A `{"glossary": [...]}` envelope works the same as a bare array."""
    respx.get(GLOSSARY_URL).respond(
        json={"glossary": [{"title": "Premium", "slug": "premium"}]},
    )

    terms = get_glossary()

    assert len(terms) == 1
    assert terms[0].title == "Premium"


@respx.mock
def test_get_articles_happy_path() -> None:
    """Articles are parsed into typed records."""
    respx.get(ARTICLES_URL).respond(
        json=[
            {"title": "How to enroll", "slug": "how-to-enroll", "url": "/how-to-enroll", "date": "2024-01-15"},
        ],
    )

    articles = get_articles()

    assert len(articles) == 1
    assert articles[0].title == "How to enroll"
    assert articles[0].url == "/how-to-enroll"


@respx.mock
def test_get_glossary_retries_on_5xx() -> None:
    """A transient 500 retries and the second response is parsed."""
    route = respx.get(GLOSSARY_URL).mock(
        side_effect=[
            httpx.Response(500, text="boom"),
            httpx.Response(200, json=[{"title": "Premium"}]),
        ],
    )

    terms = get_glossary()

    assert len(terms) == 1
    assert route.call_count == 2


@respx.mock
def test_get_glossary_does_not_retry_on_404() -> None:
    """Client errors surface immediately."""
    route = respx.get(GLOSSARY_URL).respond(404, text="not found")

    with pytest.raises(httpx.HTTPStatusError):
        get_glossary()

    assert route.call_count == 1


@respx.mock
def test_get_glossary_rejects_unexpected_payload_shape() -> None:
    """A scalar JSON value isn't something we can iterate."""
    respx.get(GLOSSARY_URL).respond(json="oops")

    with pytest.raises(TypeError, match="JSON list or object"):
        get_glossary()


@respx.mock
def test_get_glossary_rejects_wrong_inner_type() -> None:
    """A wrapped envelope whose inner value isn't a list is malformed."""
    respx.get(GLOSSARY_URL).respond(json={"glossary": "string instead of list"})

    with pytest.raises(TypeError, match="to be a list"):
        get_glossary()


@respx.mock
def test_get_articles_skips_non_dict_entries() -> None:
    """Stray non-object entries (rare, but possible) are dropped rather than crashing parsing."""
    respx.get(ARTICLES_URL).respond(json=[{"title": "Real article"}, "garbage", 42])

    articles = get_articles()

    assert len(articles) == 1
    assert articles[0].title == "Real article"


@respx.mock
def test_get_static_json_returns_records_from_bare_array() -> None:
    """`get_static_json` accepts a bare JSON array and returns the records as-is."""
    respx.get(GLOSSARY_URL).respond(
        json=[{"title": "Premium"}, {"title": "Deductible"}],
    )

    rows = get_static_json(GLOSSARY_PATH)

    assert rows == [{"title": "Premium"}, {"title": "Deductible"}]


@respx.mock
def test_get_static_json_uses_basename_for_envelope_key() -> None:
    """For a wrapped payload, `get_static_json` derives the envelope key from the path basename."""
    respx.get(ARTICLES_URL).respond(
        json={"articles": [{"title": "Enroll"}]},
    )

    rows = get_static_json(ARTICLES_PATH)

    assert rows == [{"title": "Enroll"}]


@respx.mock
def test_get_static_json_filters_non_object_entries() -> None:
    """Non-dict entries in the records list are dropped silently."""
    respx.get(GLOSSARY_URL).respond(json=[{"title": "Real"}, 42, "junk"])

    rows = get_static_json(GLOSSARY_PATH)

    assert rows == [{"title": "Real"}]
