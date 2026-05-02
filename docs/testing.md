# Testing Guide

How tests run in this repo, what the CI workflow expects from each subproject,
and how to make sure your project passes.

## Overview

- **Repo-root standards** live in `tests/` at the workspace root. They scan
  every subproject's `pyproject.toml` and assert it follows project-wide
  conventions (pytest config, coverage config, gutter widths, etc.).
- **Subproject tests** live in `<subproject>/tests/`. The CI workflow finds
  every `pyproject.toml` under the workspace root, picks the subprojects
  whose files changed in the PR, and runs `uv run pytest` in each.
- The workflow lives at `.github/workflows/test.yml` and runs on every PR
  to `main`.

## Subproject Setup

### Required Layout

Each subproject in the workspace needs:

```text
libs/<my-project>/                # or projects/<my-project>/, etc.
├── pyproject.toml                # project configuration (required)
├── src/<my_project>/             # source (src/ layout preferred)
│   └── __init__.py
└── tests/                        # tests directory (required)
    ├── __init__.py
    └── test_*.py
```

**Hard requirements** the repo-root tests enforce on every subproject that
declares `[tool.pytest.ini_options]`:

- `tests/` directory exists with an `__init__.py`.
- `pytest` and `pytest-cov` are in `dev` dependencies.
- `[tool.pytest.ini_options]` declares `minversion`, `testpaths` (must
  include `"tests"`), and `addopts`.
- `addopts` includes `--cov=<source>`, `--cov-report=term-missing`,
  `--cov-branch`, `--cov-fail-under=80`.
- `[tool.coverage.run]` declares `source`, `relative_files = true`, and
  `omit` patterns excluding tests.
- `[tool.coverage.report]` declares `exclude_lines`.
- Coverage `source` matches what `--cov` points at.
- Coverage threshold is **80%** (in `--cov-fail-under` or
  `[tool.coverage.report].fail_under`).
- Project name is lowercase.

### `pyproject.toml` Template

```toml
[project]
name = "my-project"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = []

[dependency-groups]
dev = ["pytest>=8.3.5", "pytest-cov>=6.0.0"]

[tool.pytest.ini_options]
minversion = "8.3"
testpaths = ["tests"]
addopts = ["--cov=src", "--cov-report=term-missing", "--cov-branch", "--cov-fail-under=80", "--strict-markers", "--tb=short"]

[tool.coverage.run]
source = ["src"]
relative_files = true
omit = ["tests/*", "*/tests/*", "test_*.py", "*_test.py"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "if TYPE_CHECKING:",
]
```

### Adding a Subproject to the Workspace

After creating `<path>/pyproject.toml`, register it in the root
`pyproject.toml`:

```toml
[tool.uv.workspace]
members = ["libs/my-project"]
```

Then `uv sync` from the repo root to install everything.

## Running Tests Locally

From the repo root:

```bash
# Repo-root standards tests
uv run pytest tests/

# A specific subproject
uv run --directory libs/my-project pytest

# Specific test file with verbose output
uv run --directory libs/my-project pytest tests/test_specific.py -v
```

To reproduce what CI does for a subproject:

```bash
cd libs/my-project
uv sync --dev
uv run pytest
```

## Test Authoring Notes

### Avoid External I/O

Tests should never make real HTTP requests, hit databases, or call cloud
APIs. Mock those boundaries. Use real objects for internal logic
(transformations, your own classes, etc.).

Patch where the symbol is **imported**, not where it's defined. If
`my_project/api.py` does `import httpx`, use:

```python
@patch("my_project.api.httpx.get")
def test_fetch(mock_get): ...
```

For mocks shared across many tests, put them in `tests/conftest.py` as
`autouse` fixtures.

### Coverage

- Coverage runs by default via `--cov=src` in `addopts`. Don't pass it
  on the command line — let `pyproject.toml` drive it.
- Branch coverage is enabled (`--cov-branch`).
- The 80% threshold is repo-wide. If you legitimately can't hit it for
  a specific module, add it to `[tool.coverage.run].omit` rather than
  lowering the threshold.

## CI Workflow Behavior

`.github/workflows/test.yml` runs three jobs on every PR:

1. **`discover_projects`** — scans for `pyproject.toml` files (excluding
   the workspace root) and outputs the list of subprojects whose files
   changed in the PR.
2. **`validate_standards`** — runs the repo-root `tests/` suite. This
   catches misconfigured subprojects before their tests even run.
3. **`test_projects`** — matrix job over the changed subprojects from
   step 1; runs `uv run pytest` in each.

The workflow uses `ubuntu-latest` runners and the workspace-root
`uv.lock` — no AWS, no dbt, no extra runtime wiring.
