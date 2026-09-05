# Development

How this repo is built and maintained. It's a solo portfolio project,
so some of the tooling you'll find here serves the maintainer's
workflow rather than end users — this page explains what each piece is
for.

## Dev environment

The repo is a single [uv](https://docs.astral.sh/uv/) workspace: the
Python library, Dagster project, and dbt project are workspace members
sharing one lockfile. To set up:

```bash
uv sync --all-packages --all-groups
uv run pre-commit install
```

Local checks closely mirror CI. `uv run pre-commit run --all-files`
reproduces the lint workflow, and [`scripts/local-ci/`](../scripts/local-ci/)
holds the script that reproduces the per-subproject test matrix — the
idea being that anything CI would reject should fail on the developer's
machine first.

## Agent-assisted development

This repo is developed with [Claude Code](https://claude.com/claude-code).
The agent-facing configuration is checked in and public:

- [`CLAUDE.md`](../CLAUDE.md) / [`AGENTS.md`](../AGENTS.md) — project
  conventions the agent follows: git workflow, commit format, linting
  and local/CI-parity hooks.
- [`REVIEW.md`](../REVIEW.md) — instructions for the automated PR
  reviewer: what to flag, at what severity, and what to skip.
- [`.github/workflows/claude-review.yml`](../.github/workflows/claude-review.yml)
  — runs that reviewer on every PR, gated on the `Code Quality Check`
  and `Test` workflows succeeding first so review effort isn't spent
  on code that deterministic checks already reject.

## Ralph loops

[`scripts/ralph/`](../scripts/ralph/README.md) is a maintainer-only
toolkit for running autonomous agent loops ("Ralph Wiggum" loops):
each run drives a headless Claude session in its own sibling git
worktree until a completion sentinel fires or the iteration cap is
reached, aiming to leave a feature branch ready for a normal PR. It
has a one-time billing-cap prerequisite and several layers of cost
control; see its README for usage and details.

## Repo standards tests

[`tests/`](../tests/) at the workspace root doesn't test data code —
it tests the repo itself. The suite walks every subproject's
`pyproject.toml` and asserts project-wide standards: pytest and
coverage configuration, an 80% coverage floor, project layout
conventions, and that the generated dbt sources YAML stays in sync
with the dataset registry. In a workspace where subprojects are added
over time — often by agents — these meta-tests keep every member held
to the same bar without relying on review vigilance. See
[`docs/testing.md`](testing.md) for the full requirements and how the
CI test workflow runs them.
