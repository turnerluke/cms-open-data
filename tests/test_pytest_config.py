"""Validate pytest configuration standards across all subprojects."""

from pathlib import Path
import tomllib

from .conftest import discover_subprojects

import pytest


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_pytest_config_exists(pyproject_path: Path) -> None:
    """Verify pytest configuration exists if the `tests/` directory is present."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip(f"no tests directory in {project_dir.name}")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    assert "tool" in config, f"{pyproject_path}: missing [tool] section"
    assert "pytest" in config["tool"], f"{pyproject_path}: missing [tool.pytest.ini_options]"


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_pytest_required_fields(pyproject_path: Path) -> None:
    """Verify pytest configuration has the required fields."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    pytest_config = config.get("tool", {}).get("pytest", {}).get("ini_options", {})

    assert "minversion" in pytest_config, f"{pyproject_path}: missing minversion"
    assert "testpaths" in pytest_config, f"{pyproject_path}: missing testpaths"
    assert "addopts" in pytest_config, f"{pyproject_path}: missing addopts"
    assert "tests" in pytest_config["testpaths"], f"{pyproject_path}: testpaths should include 'tests'"


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_pytest_required_addopts(pyproject_path: Path) -> None:
    """Verify pytest addopts include the required coverage flags."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    addopts = config.get("tool", {}).get("pytest", {}).get("ini_options", {}).get("addopts", [])
    addopts_str = addopts if isinstance(addopts, str) else " ".join(addopts)

    required_flags = [
        "--cov",
        "--cov-report=term-missing",
        "--cov-branch",
        "--cov-fail-under",
    ]
    for flag in required_flags:
        assert flag in addopts_str, f"{pyproject_path}: addopts missing required flag: {flag}"

    has_cov_source = any(opt.startswith("--cov=") for opt in addopts if isinstance(addopts, list)) or "--cov=" in addopts_str
    assert has_cov_source, f"{pyproject_path}: addopts must include --cov=<source>"


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_pytest_dependencies(pyproject_path: Path) -> None:
    """Verify `pytest` and `pytest-cov` are in dev dependencies."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    dev_deps = config.get("project", {}).get("optional-dependencies", {}).get("dev", []) or config.get(
        "dependency-groups", {}
    ).get("dev", [])
    dev_deps_str = " ".join(dev_deps)

    assert "pytest" in dev_deps_str, f"{pyproject_path}: pytest not in dev dependencies"
    assert "pytest-cov" in dev_deps_str, f"{pyproject_path}: pytest-cov not in dev dependencies"
