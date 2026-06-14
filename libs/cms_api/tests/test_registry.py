"""Tests for the declarative dataset registry."""

from __future__ import annotations

from pathlib import Path

from cms_api import DatasetSpec, load_registry

import pytest


REGISTRY_PATH = Path(__file__).resolve().parents[1] / "datasets.toml"


def test_real_datasets_toml_validates() -> None:
    """Every row in the checked-in datasets.toml validates as a DatasetSpec."""
    specs = load_registry(REGISTRY_PATH)
    assert len(specs) >= 1
    assert all(isinstance(s, DatasetSpec) for s in specs)


def test_load_registry_default_path_loads_checked_in_file() -> None:
    """Calling load_registry() with no args reads the checked-in TOML."""
    specs = load_registry()
    assert len(specs) >= 1


def test_registry_keys_are_unique() -> None:
    """No two registry rows may share a key (asset names would collide)."""
    specs = load_registry(REGISTRY_PATH)
    keys = [s.key for s in specs]
    assert sorted(set(keys)) == sorted(keys)


def test_socrata_spec_requires_dataset_id() -> None:
    """A socrata row missing dataset_id fails validation."""
    with pytest.raises(ValueError, match="dataset_id"):
        DatasetSpec.model_validate(
            {
                "key": "bad_socrata",
                "source": "socrata",
                "description": "x",
                "group": "cms_raw",
            },
        )


def test_socrata_spec_rejects_path() -> None:
    """A socrata row with `path` set fails validation — wrong source field."""
    with pytest.raises(ValueError, match="must not set"):
        DatasetSpec.model_validate(
            {
                "key": "weird_socrata",
                "source": "socrata",
                "dataset_id": "abcd-1234",
                "path": "/api/x.json",
                "description": "x",
                "group": "cms_raw",
            },
        )


def test_healthcare_gov_spec_requires_path() -> None:
    """A healthcare_gov row missing path fails validation."""
    with pytest.raises(ValueError, match="path"):
        DatasetSpec.model_validate(
            {
                "key": "bad_hgov",
                "source": "healthcare_gov",
                "description": "x",
                "group": "cms_raw",
            },
        )


def test_healthcare_gov_spec_rejects_dataset_id() -> None:
    """A healthcare_gov row with `dataset_id` set fails validation."""
    with pytest.raises(ValueError, match="must not set"):
        DatasetSpec.model_validate(
            {
                "key": "weird_hgov",
                "source": "healthcare_gov",
                "path": "/api/x.json",
                "dataset_id": "abcd-1234",
                "description": "x",
                "group": "cms_raw",
            },
        )


def test_unknown_source_rejected() -> None:
    """Sources outside the configured Literal are rejected."""
    with pytest.raises(ValueError, match="source"):
        DatasetSpec.model_validate(
            {
                "key": "from_mars",
                "source": "martian",
                "description": "x",
                "group": "cms_raw",
            },
        )


def test_load_registry_accepts_custom_path(tmp_path: Path) -> None:
    """load_registry honours an explicit path argument."""
    custom = tmp_path / "datasets.toml"
    custom.write_text(
        "[[dataset]]\n"
        'key = "custom_one"\n'
        'source = "socrata"\n'
        'dataset_id = "abcd-1234"\n'
        'description = "custom dataset"\n'
        'group = "test_group"\n',
    )
    specs = load_registry(custom)
    assert len(specs) == 1
    assert specs[0].key == "custom_one"
    assert specs[0].dataset_id == "abcd-1234"


def test_load_registry_rejects_non_array_dataset(tmp_path: Path) -> None:
    """A non-array top-level `dataset` key is a malformed TOML file."""
    custom = tmp_path / "datasets.toml"
    custom.write_text('[dataset]\nkey = "oops"\n')
    with pytest.raises(TypeError, match="dataset"):
        load_registry(custom)


def test_load_registry_handles_empty_file(tmp_path: Path) -> None:
    """An empty TOML file is allowed; it just returns no specs."""
    custom = tmp_path / "datasets.toml"
    custom.write_text("")
    assert load_registry(custom) == []
