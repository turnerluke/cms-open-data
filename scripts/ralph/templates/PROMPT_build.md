# Ralph build-mode prompt

You are running in **build mode** of a Ralph Wiggum loop. Each iteration runs in a fresh context with no memory of prior runs.
State persists only on disk and in git history on this branch.

## Inputs to read every iteration

- `RALPH/AGENTS_RALPH.md` — operational crib sheet (read first).
- `RALPH/IMPLEMENTATION_PLAN.md` — the prioritized checklist; your work queue.
- `RALPH/specs/*.md` — operator-owned source of truth.
- Project root `AGENTS.md` — repo-wide conventions (commit format, lint, PR rules).
- `git log main..HEAD` — your record of what prior iterations have done.

## Task — exactly one item per iteration

1. Read `RALPH/AGENTS_RALPH.md`, then `RALPH/IMPLEMENTATION_PLAN.md`.
2. Pick the highest-priority `- [ ]` item.
3. Implement only that item. Read the relevant code, then make the change.
4. Run targeted tests: `uv run pytest <path/to/test>`. Iterate until green.
5. Run `uv run pre-commit run --files <changed-files>` and fix anything it reports.
6. Commit using the project's heredoc conventional-commit format (see `AGENTS.md` → "Commit Message Format"). **Do not** add
   co-author trailers. Backtick uppercase identifiers in the subject.
7. Mark the item `- [x]` in `RALPH/IMPLEMENTATION_PLAN.md` and add a one-line `Notes:` sub-bullet if anything surprising came
   up.

## Stopping

Emit `<promise>RALPH_DONE</promise>` on its own line **only** when every item in `RALPH/IMPLEMENTATION_PLAN.md` is `- [x]` and
`uv run pre-commit run --all-files` is clean.

Otherwise: finish the one item, commit, update the plan, and end the turn. The loop will run you again with a fresh context.

## Hard rules

- One logical unit per iteration. If the next plan item is too large, **split it in the plan first**, commit the plan update
  by itself, and stop — the next iteration will pick up the smaller pieces.
- Never push to a remote. Never run `gh pr create`. The operator does that after reviewing your commits.
- Never edit files under `RALPH/specs/` — specs are operator-owned.
- Never edit `RALPH/PROMPT_*.md` or `RALPH/AGENTS_RALPH.md` — those are operator-owned too.
