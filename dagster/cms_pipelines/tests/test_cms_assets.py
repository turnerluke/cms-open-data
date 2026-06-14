"""Materialization tests for the `cms_*` raw-extraction assets.

The `cms_api` callables that each asset depends on are monkey-patched to
return synthetic Pydantic records, so these tests cover the assets'
pyarrow + IO-manager wiring without touching the public CMS APIs.
"""

from collections.abc import Iterator
from pathlib import Path
from typing import Any

from cms_api import Article, GlossaryTerm, NppesProvider, PartDSpendingByDrug
from cms_pipelines.defs.cms import healthcare_gov, nppes, socrata
from cms_pipelines.defs.cms.io_manager import RawParquetIOManager
import pyarrow.parquet as pq

from dagster import AssetsDefinition, ExecuteInProcessResult, materialize

import pytest


def _materialize(
    asset: AssetsDefinition,
    tmp_path: Path,
    *,
    run_config: dict[str, Any] | None = None,
    raise_on_error: bool = True,
) -> ExecuteInProcessResult:
    """Materialize `asset` against a fresh `RawParquetIOManager` rooted at `tmp_path`."""
    return materialize(
        [asset],
        resources={"cms_raw_io_manager": RawParquetIOManager(root=str(tmp_path))},
        run_config=run_config or {},
        raise_on_error=raise_on_error,
    )


def _only_parquet(tmp_path: Path, asset_name: str) -> Path:
    """Return the single Parquet file the asset run wrote under `<tmp>/<asset_name>/`."""
    files = list((tmp_path / asset_name).glob("*.parquet"))
    assert len(files) == 1, f"expected exactly one parquet under {asset_name}, got {files}"
    return files[0]


def test_part_d_asset_materializes_to_parquet(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """The Part D asset writes one Parquet file with all rows from the upstream iterator."""
    sample = [
        PartDSpendingByDrug.model_validate(
            {"brnd_name": "DrugA", "gnrc_name": "drug-a", "mftr_name": "AcmePharma"},
        ),
        PartDSpendingByDrug.model_validate(
            {"brnd_name": "DrugB", "gnrc_name": "drug-b", "mftr_name": "BetaPharma"},
        ),
    ]
    monkeypatch.setattr(socrata, "iter_part_d_spending_by_drug", lambda: iter(sample))

    result = _materialize(socrata.cms_part_d_spending_by_drug, tmp_path)

    assert result.success
    table = pq.read_table(_only_parquet(tmp_path, "cms_part_d_spending_by_drug"))
    assert table.num_rows == 2
    assert "brnd_name" in table.column_names


def test_part_d_asset_fails_on_empty_extract(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """An empty Part D extract fails loudly rather than silently landing an empty Parquet."""

    def _empty() -> Iterator[PartDSpendingByDrug]:
        return iter([])

    monkeypatch.setattr(socrata, "iter_part_d_spending_by_drug", _empty)

    with pytest.raises(Exception, match="zero rows"):
        _materialize(socrata.cms_part_d_spending_by_drug, tmp_path)


def test_glossary_asset_materializes(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Healthcare.gov glossary terms land in a single Parquet."""
    terms = [
        GlossaryTerm.model_validate({"title": "Premium", "slug": "premium", "content": "..."}),
        GlossaryTerm.model_validate({"title": "Deductible", "slug": "deductible", "content": "..."}),
    ]
    monkeypatch.setattr(healthcare_gov, "get_glossary", lambda: terms)

    result = _materialize(healthcare_gov.cms_healthcare_gov_glossary, tmp_path)

    assert result.success
    table = pq.read_table(_only_parquet(tmp_path, "cms_healthcare_gov_glossary"))
    assert table.num_rows == 2
    assert "title" in table.column_names


def test_glossary_asset_fails_on_empty_corpus(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """An empty glossary corpus is treated as an extraction failure."""
    monkeypatch.setattr(healthcare_gov, "get_glossary", list)

    with pytest.raises(Exception, match="zero terms"):
        _materialize(healthcare_gov.cms_healthcare_gov_glossary, tmp_path)


def test_articles_asset_materializes(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Healthcare.gov articles land in a single Parquet."""
    articles = [
        Article.model_validate(
            {"title": "Enrollment", "slug": "enrollment", "url": "/enrollment", "date": "2026-01-15"},
        ),
    ]
    monkeypatch.setattr(healthcare_gov, "get_articles", lambda: articles)

    result = _materialize(healthcare_gov.cms_healthcare_gov_articles, tmp_path)

    assert result.success
    table = pq.read_table(_only_parquet(tmp_path, "cms_healthcare_gov_articles"))
    assert table.num_rows == 1


def test_articles_asset_fails_on_empty_corpus(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """An empty article corpus is treated as an extraction failure."""
    monkeypatch.setattr(healthcare_gov, "get_articles", list)

    with pytest.raises(Exception, match="zero records"):
        _materialize(healthcare_gov.cms_healthcare_gov_articles, tmp_path)


def test_nppes_state_sweep_collects_per_state(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Two states, one provider each → two rows in the landed Parquet."""

    def fake_search(*, enumeration_type: str, state: str) -> Iterator[NppesProvider]:
        yield NppesProvider.model_validate(
            {
                "number": "1234567890",
                "enumeration_type": enumeration_type,
                "basic": {"organization_name": f"Org in {state}"},
                "addresses": [{"state": state, "address_purpose": "LOCATION"}],
                "taxonomies": [],
            },
        )

    monkeypatch.setattr(nppes, "search_providers", fake_search)

    run_config = {"ops": {"cms_nppes_providers": {"config": {"states": ["CA", "TX"]}}}}
    result = _materialize(nppes.cms_nppes_providers, tmp_path, run_config=run_config)

    assert result.success
    table = pq.read_table(_only_parquet(tmp_path, "cms_nppes_providers"))
    assert table.num_rows == 2


def test_nppes_sweep_fails_when_every_state_empty(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """If every state's search returns zero rows the asset fails — no empty Parquet lands."""

    def empty_search(*, enumeration_type: str, state: str) -> Iterator[NppesProvider]:
        del enumeration_type, state
        return iter([])

    monkeypatch.setattr(nppes, "search_providers", empty_search)

    run_config = {"ops": {"cms_nppes_providers": {"config": {"states": ["CA"]}}}}
    with pytest.raises(Exception, match="zero providers"):
        _materialize(nppes.cms_nppes_providers, tmp_path, run_config=run_config)
