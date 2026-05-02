"""Validate coverage configuration standards across all subprojects."""

from pathlib import Path
import tomllib

from .conftest import discover_subprojects

import pytest


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_coverage_run_config(pyproject_path: Path) -> None:
    """Verify `[tool.coverage.run]` configuration."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    coverage_run = config.get("tool", {}).get("coverage", {}).get("run", {})
    assert coverage_run, f"{pyproject_path}: missing [tool.coverage.run]"

    assert "source" in coverage_run, f"{pyproject_path}: missing coverage source"
    assert "relative_files" in coverage_run, f"{pyproject_path}: missing relative_files"
    assert "omit" in coverage_run, f"{pyproject_path}: missing omit patterns"

    assert coverage_run["relative_files"] is True, (
        f"{pyproject_path}: relative_files should be true for cross-environment compatibility"
    )

    omit = coverage_run["omit"]
    assert any("test" in pattern.lower() for pattern in omit), f"{pyproject_path}: omit should exclude test files"


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_coverage_report_config(pyproject_path: Path) -> None:
    """Verify `[tool.coverage.report]` configuration."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    coverage_report = config.get("tool", {}).get("coverage", {}).get("report", {})
    assert coverage_report, f"{pyproject_path}: missing [tool.coverage.report]"
    assert "exclude_lines" in coverage_report, f"{pyproject_path}: missing exclude_lines (for pragma: no cover, etc.)"


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_coverage_threshold_is_80(pyproject_path: Path) -> None:
    """Verify coverage threshold is 80%."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    addopts = config.get("tool", {}).get("pytest", {}).get("ini_options", {}).get("addopts", [])
    pytest_threshold: int | None = None
    if isinstance(addopts, str):
        if "--cov-fail-under=" in addopts:
            parts = addopts.split("--cov-fail-under=")
            if len(parts) > 1:
                pytest_threshold = int(parts[1].split()[0])
    else:
        for opt in addopts:
            if "--cov-fail-under=" in opt:
                pytest_threshold = int(opt.split("=")[1])
                break

    coverage_threshold = config.get("tool", {}).get("coverage", {}).get("report", {}).get("fail_under")

    assert pytest_threshold == 80 or coverage_threshold == 80, (
        f"{pyproject_path}: coverage threshold should be 80% (found pytest={pytest_threshold}, coverage={coverage_threshold})"
    )


@pytest.mark.parametrize("pyproject_path", discover_subprojects())
def test_coverage_source_matches_structure(pyproject_path: Path) -> None:
    """Verify coverage source configuration matches the project's layout."""
    project_dir = pyproject_path.parent
    if not (project_dir / "tests").exists():
        pytest.skip("no tests directory")

    with pyproject_path.open("rb") as f:
        config = tomllib.load(f)

    coverage_source = config.get("tool", {}).get("coverage", {}).get("run", {}).get("source", [])
    has_src_dir = (project_dir / "src").exists()

    if has_src_dir:
        assert "src" in coverage_source or any(src.startswith("src/") for src in coverage_source), (
            f"{project_dir.name}: has src/ layout but coverage source doesn't include 'src' or 'src/*': {coverage_source}"
        )
    else:
        assert coverage_source, f"{project_dir.name}: coverage source is empty"
