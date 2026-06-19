"""Materialization tests for the `cms_*` raw-extraction assets.

The `cms_api` callables that each asset depends on are monkey-patched to
return synthetic records, so these tests cover the assets' pyarrow + IO-manager
wiring without touching the public CMS APIs.

Registry-driven assets are tested via the `registry_assets` factory module
(one materialization per row in `datasets.toml`); the hand-written NPPES
sweep keeps its own targeted tests below.
"""

from collections.abc import Iterator
from pathlib import Path

from cms_api import DatasetSpec, JsonObject, NppesProvider, load_registry
from cms_pipelines.defs.cms import nppes, registry_assets
from cms_pipelines.defs.io_managers.parquet import ParquetIOManager
import pyarrow.parquet as pq

from dagster import AssetsDefinition, ExecuteInProcessResult, materialize

import pytest


def _io_manager(tmp_path: Path) -> ParquetIOManager:
    """Build a `ParquetIOManager` rooted at `tmp_path` for a single test run."""
    return ParquetIOManager(root=str(tmp_path))


def _materialize(asset_def: AssetsDefinition, tmp_path: Path) -> ExecuteInProcessResult:
    """Materialize `asset_def` against a fresh `ParquetIOManager` rooted at `tmp_path`."""
    return materialize([asset_def], resources={"parquet_io_manager": _io_manager(tmp_path)})


def _materialize_nppes(tmp_path: Path, *, states: list[str]) -> ExecuteInProcessResult:
    """Materialize the NPPES asset with the given state list as its `Config.states`."""
    return materialize(
        [nppes.cms_nppes_providers],
        resources={"parquet_io_manager": _io_manager(tmp_path)},
        run_config={"ops": {"cms_nppes_providers": {"config": {"states": states}}}},
    )


def _only_parquet(tmp_path: Path, asset_name: str) -> Path:
    """Return the single Parquet file the asset run wrote under `<tmp>/<asset_name>/`."""
    files = list((tmp_path / asset_name).glob("*.parquet"))
    assert len(files) == 1, f"expected exactly one parquet under {asset_name}, got {files}"
    return files[0]


def _registry_asset(spec: DatasetSpec) -> AssetsDefinition:
    """Look up the generated asset for `spec` by its canonical `cms_<key>` name."""
    return getattr(registry_assets, f"cms_{spec.key}")


_NON_REGISTRY_ASSET_SOURCES = {
    "dkan_data_api_bulk",
    "dkan_medicaid_bulk",
    "dkan_open_payments_bulk",
    "dkan_healthcare_gov_zip",
}


def test_one_asset_emitted_per_registry_row() -> None:
    """Every JSON-paginated registry row resolves to an `AssetsDefinition`.

    Sources with a different fetcher contract live on peer modules and are
    checked there instead: bulk-CSV (``dkan_data_api_bulk``,
    ``dkan_medicaid_bulk``, ``dkan_open_payments_bulk``) on
    ``bulk_csv_assets``; QHP ZIP-XLSX (``dkan_healthcare_gov_zip``) on
    ``qhp_zip_assets``.
    """
    for spec in load_registry():
        if spec.source in _NON_REGISTRY_ASSET_SOURCES:
            continue
        asset_def = _registry_asset(spec)
        assert isinstance(asset_def, AssetsDefinition)
        assert asset_def.key.path[-1] == f"cms_{spec.key}"


def test_socrata_registry_asset_materializes(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A Socrata-sourced registry asset lands rows from `iter_dataset` as Parquet."""
    sample: list[JsonObject] = [
        {"brnd_name": "DrugA", "gnrc_name": "drug-a"},
        {"brnd_name": "DrugB", "gnrc_name": "drug-b"},
    ]

    def fake_iter_dataset(dataset_id: str, *, domain: str) -> Iterator[JsonObject]:
        del dataset_id, domain
        return iter(sample)

    monkeypatch.setattr(registry_assets, "iter_dataset", fake_iter_dataset)

    socrata_specs = [s for s in load_registry() if s.source == "socrata"]
    assert socrata_specs, "expected at least one socrata-sourced registry row"
    spec = socrata_specs[0]
    asset_def = _registry_asset(spec)

    result = _materialize(asset_def, tmp_path)

    assert result.success
    table = pq.read_table(_only_parquet(tmp_path, f"cms_{spec.key}"))
    assert table.num_rows == 2
    assert "brnd_name" in table.column_names


def test_healthcare_gov_registry_asset_materializes(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A healthcare_gov-sourced registry asset lands records from `get_static_json`."""
    captured_paths: list[str] = []

    def fake_get_static_json(path: str) -> list[JsonObject]:
        captured_paths.append(path)
        return [{"title": "term", "slug": "term"}]

    monkeypatch.setattr(registry_assets, "get_static_json", fake_get_static_json)

    hgov_specs = [s for s in load_registry() if s.source == "healthcare_gov"]
    assert hgov_specs, "expected at least one healthcare_gov-sourced registry row"
    spec = hgov_specs[0]
    asset_def = _registry_asset(spec)

    result = _materialize(asset_def, tmp_path)

    assert result.success
    assert captured_paths == [spec.path]
    table = pq.read_table(_only_parquet(tmp_path, f"cms_{spec.key}"))
    assert table.num_rows == 1
    assert "title" in table.column_names


def test_dkan_provider_data_registry_asset_materializes(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A dkan_provider_data-sourced registry asset lands rows from `iter_provider_data_catalog`."""
    sample: list[JsonObject] = [
        {"facility_id": "010001", "facility_name": "Hospital A"},
        {"facility_id": "010002", "facility_name": "Hospital B"},
    ]
    captured_ids: list[str] = []

    def fake_iter(dataset_id: str) -> Iterator[JsonObject]:
        captured_ids.append(dataset_id)
        return iter(sample)

    monkeypatch.setattr(registry_assets, "iter_provider_data_catalog", fake_iter)

    dkan_specs = [s for s in load_registry() if s.source == "dkan_provider_data"]
    assert dkan_specs, "expected at least one dkan_provider_data-sourced registry row"
    spec = dkan_specs[0]
    asset_def = _registry_asset(spec)

    result = _materialize(asset_def, tmp_path)

    assert result.success
    assert captured_ids == [spec.dataset_id]
    table = pq.read_table(_only_parquet(tmp_path, f"cms_{spec.key}"))
    assert table.num_rows == 2
    assert "facility_name" in table.column_names


def test_registry_asset_fails_on_empty_socrata_extract(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """An empty Socrata response trips the zero-row guard."""

    def empty_iter(dataset_id: str, *, domain: str) -> Iterator[JsonObject]:
        del dataset_id, domain
        return iter([])

    monkeypatch.setattr(registry_assets, "iter_dataset", empty_iter)

    spec = next(s for s in load_registry() if s.source == "socrata")
    asset_def = _registry_asset(spec)

    with pytest.raises(Exception, match="zero rows"):
        _materialize(asset_def, tmp_path)


def test_registry_asset_fails_on_empty_healthcare_gov_extract(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """An empty healthcare.gov response trips the zero-row guard."""
    monkeypatch.setattr(registry_assets, "get_static_json", lambda _path: [])

    spec = next(s for s in load_registry() if s.source == "healthcare_gov")
    asset_def = _registry_asset(spec)

    with pytest.raises(Exception, match="zero rows"):
        _materialize(asset_def, tmp_path)


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

    result = _materialize_nppes(tmp_path, states=["CA", "TX"])

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

    with pytest.raises(Exception, match="zero providers"):
        _materialize_nppes(tmp_path, states=["CA"])
