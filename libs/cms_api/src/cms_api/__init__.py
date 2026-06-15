"""Sync client library for CMS, Medicaid, Healthcare.gov, and NPPES public APIs."""

from ._types import JsonObject, JsonValue
from .dkan import get_data_api_csv_url, get_medicaid_dataset_csv_url, iter_provider_data_catalog
from .healthcare_gov import Article, GlossaryTerm, get_articles, get_glossary, get_static_json
from .nppes import NppesAddress, NppesBasic, NppesProvider, NppesTaxonomy, get_provider_by_npi, search_providers
from .registry import DatasetSpec, load_registry
from .socrata import CMS_DOMAIN, MEDICAID_DOMAIN, iter_dataset


__all__ = [
    "CMS_DOMAIN",
    "MEDICAID_DOMAIN",
    "Article",
    "DatasetSpec",
    "GlossaryTerm",
    "JsonObject",
    "JsonValue",
    "NppesAddress",
    "NppesBasic",
    "NppesProvider",
    "NppesTaxonomy",
    "get_articles",
    "get_data_api_csv_url",
    "get_glossary",
    "get_medicaid_dataset_csv_url",
    "get_provider_by_npi",
    "get_static_json",
    "iter_dataset",
    "iter_provider_data_catalog",
    "load_registry",
    "search_providers",
]
