"""Sync client library for CMS, Medicaid, Healthcare.gov, and NPPES public APIs."""

from .healthcare_gov import Article, GlossaryTerm, get_articles, get_glossary
from .nppes import NppesAddress, NppesBasic, NppesProvider, NppesTaxonomy, get_provider_by_npi, search_providers
from .socrata import (
    CMS_DOMAIN,
    DATASET_PART_D_SPENDING_BY_DRUG,
    MEDICAID_DOMAIN,
    PartDSpendingByDrug,
    iter_dataset,
    iter_part_d_spending_by_drug,
)


__all__ = [
    "CMS_DOMAIN",
    "DATASET_PART_D_SPENDING_BY_DRUG",
    "MEDICAID_DOMAIN",
    "Article",
    "GlossaryTerm",
    "NppesAddress",
    "NppesBasic",
    "NppesProvider",
    "NppesTaxonomy",
    "PartDSpendingByDrug",
    "get_articles",
    "get_glossary",
    "get_provider_by_npi",
    "iter_dataset",
    "iter_part_d_spending_by_drug",
    "search_providers",
]
