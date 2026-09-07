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

## Dashboard deploy pipeline

[`.github/workflows/warehouse.yml`](../.github/workflows/warehouse.yml)
rebuilds everything from scratch weekly (Mondays 05:17 UTC): fresh CMS
downloads via Dagster, `dbt build`, the Evidence static site, then a
deploy to GitHub Pages at
<https://turnerluke.github.io/cms-open-data/>. To re-deploy manually,
trigger the workflow from the Actions tab or run:

```bash
gh workflow run "Warehouse Build"
```

Gotcha: GitHub automatically disables scheduled workflows after 60
days without repository activity. If the site goes stale, check the
Actions tab for a "workflow disabled" banner and re-enable it.

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
- [`.claude/agents/`](../.claude/agents/) — two custom sub-agent
  definitions codifying the sprint workflow that produced ~20 PRs
  across four sprints, so orchestration sessions don't re-derive the
  same brief every time:

    - [`implementer.md`](../.claude/agents/implementer.md) — builds
      one PR-sized change in a dedicated worktree, runs the local
      gates, and returns a ready-to-paste PR title and body. Makes
      exactly one commit; does not push or open the PR.
    - [`adversarial-reviewer.md`](../.claude/agents/adversarial-reviewer.md)
      — given the resulting commit SHA, independently re-verifies each
      claim against real data and returns an `APPROVE` / `NEEDS FIXES`
      verdict with bucketed findings. Read-only; never edits files.

    The intended loop is implement in a worktree → adversarial review →
    address findings → orchestrator opens the PR → poll CI to green.

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
