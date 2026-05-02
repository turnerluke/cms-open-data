"""Validate project structure standards across all subprojects."""

from pathlib import Path
import tomllib

from .conftest import discover_subprojects

import pytest


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_tests_directory_exists_if_pytest_config(pyproject_path: Path) -> None:
    """Verify a `tests/` directory exists if pytest config is present."""
    project_dir = pyproject_path.parent
    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    has_pytest_config = "pytest" in config.get("tool", {})
    has_tests_dir = (project_dir / "tests").exists()

    if has_pytest_config:
        assert has_tests_dir, f"{project_dir.name}: has pytest config but no tests/ directory"


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_tests_directory_has_init(pyproject_path: Path) -> None:
    """Verify the `tests/` directory has an `__init__.py`."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    init_file = project_dir / "tests" / "__init__.py"
    assert init_file.exists(), f"{project_dir.name}: tests/ directory should have __init__.py"


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_cov_source_in_addopts_matches_coverage_run_source(pyproject_path: Path) -> None:
    """Verify `--cov` in pytest addopts matches `[tool.coverage.run].source`."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    addopts = config.get("tool", {}).get("pytest", {}).get("ini_options", {}).get("addopts", [])
    cov_sources_from_addopts: list[str] = []
    if isinstance(addopts, str):
        cov_sources_from_addopts.extend(part.split("=", 1)[1] for part in addopts.split() if part.startswith("--cov="))
    else:
        cov_sources_from_addopts.extend(opt.split("=", 1)[1] for opt in addopts if opt.startswith("--cov="))

    coverage_sources = config.get("tool", {}).get("coverage", {}).get("run", {}).get("source", [])

    if coverage_sources:
        assert set(cov_sources_from_addopts) == set(coverage_sources), (
            f"{project_dir.name}: --cov sources {cov_sources_from_addopts} don't match coverage.run sources {coverage_sources}"
        )


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_project_name_is_lowercase(pyproject_path: Path) -> None:
    """Verify project name is lowercase (with hyphens, not underscores)."""
    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    project_name = config.get("project", {}).get("name")
    if project_name:
        assert project_name == project_name.lower(), (
            f"{pyproject_path.parent.name}: project name '{project_name}' should be lowercase"
        )
