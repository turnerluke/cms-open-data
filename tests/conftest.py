"""Shared fixtures for pytest standards validation tests."""

from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]


def discover_subprojects() -> list[Path]:
    """Find all `pyproject.toml` files in the monorepo, excluding the workspace root.

    Skips paths under any dot-prefixed directory (`.venv`, `.git`, etc.) and
    `node_modules`. Returns a sorted list of paths.
    """
    projects = list(REPO_ROOT.glob("**/pyproject.toml"))
    return sorted(
        p
        for p in projects
        if p.parent != REPO_ROOT and not any(part.startswith(".") or part == "node_modules" for part in p.parts)
    )


@pytest.fixture
def subproject_paths() -> list[Path]:
    """Fixture providing all subproject `pyproject.toml` paths."""
    return discover_subprojects()
