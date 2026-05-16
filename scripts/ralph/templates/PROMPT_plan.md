# Ralph plan-mode prompt

You are running in **plan mode** of a Ralph Wiggum loop. Each iteration runs in a fresh context with no memory of prior runs.
State persists only on disk.

## Inputs to read every iteration

- `RALPH/specs/*.md` — operator-owned source of truth for what this feature must do.
- `RALPH/AGENTS_RALPH.md` — operational crib sheet (read first).
- `RALPH/IMPLEMENTATION_PLAN.md` — your shared state across iterations (may not exist yet on iteration 1).
- Project root `AGENTS.md` — repo-wide conventions (commit format, lint, PR rules).
- Relevant code under `src/`, `libs/`, `dagster/`, `dbt/`, `tests/`.

## Task

Perform gap analysis between the specs and the current repo state, then update `RALPH/IMPLEMENTATION_PLAN.md` with a
prioritized markdown checklist of the work needed to fulfill the specs.

**Do not implement anything. Do not edit source code. Do not commit.** This iteration only writes (or rewrites)
`RALPH/IMPLEMENTATION_PLAN.md`.

Each checklist item must:

- Start with `- [ ]`.
- Be one concrete, verifiable unit of work — typically a single file edit or one cohesive change.
- Include a one-line rationale in parentheses if the intent isn't obvious from the title.

If `RALPH/IMPLEMENTATION_PLAN.md` already exists:

- Preserve `- [x]` items where they are; do not re-open completed work.
- Update unchecked items to reflect the current code state and any new gaps you spot.
- Reorder by priority if needed.

## Stopping

Emit `<promise>RALPH_DONE</promise>` on its own line **only** when:

1. The plan completely covers every spec in `RALPH/specs/`.
2. No new gaps are discoverable by re-reading specs vs. code.

Otherwise: write the updated plan and end the turn normally. The loop will run you again with a fresh context.
