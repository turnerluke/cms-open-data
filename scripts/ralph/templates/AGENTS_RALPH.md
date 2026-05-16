# Ralph operational guide

Read this every iteration. Kept brief on purpose so it doesn't crowd the context window.

## Project basics

- Python project; dependencies managed by `uv`. Always run Python tools via `uv run`.
- Run tests: `uv run pytest [path::test]`.
- Run linters: `uv run pre-commit run --all-files` (or `--files <changed>` for a subset).
- Format Python: `uv run ruff format`. A PostToolUse hook formats `.py` files automatically on edit, so manual runs are rarely
  needed.

## Commit message format (strictly enforced)

- Conventional commit: `type(scope): subject` where `type` ∈ {feat, fix, docs, style, refactor, test, chore, ci, build, perf}.
- Subject ≤ 72 chars. Wrap body lines at ~72 chars (gitlint enforces 100).
- Backtick uppercase identifiers in the subject: ``chore: add `MIT` license`` (not `chore: add MIT license`).
- **Always** use a heredoc, never multiple `-m` flags:

    ```bash
    git commit -m "$(cat <<'EOF'
    feat: short subject under 72 chars

    Body wrapped at ~72 columns so gitlint's 100-char body-line-length
    cap isn't hit.
    EOF
    )"
    ```

- **Never** add `Co-Authored-By:` trailers (including for Claude).

## Where things live

- Source code: `src/`, `libs/`, `dagster/`, `dbt/`.
- Tests: `tests/`.
- Specs you must satisfy: `RALPH/specs/`.
- Your work queue: `RALPH/IMPLEMENTATION_PLAN.md`.
- Iteration log (read-only for you): `RALPH/ralph.log`.

## Iteration discipline

- One logical commit per iteration.
- Update `RALPH/IMPLEMENTATION_PLAN.md` as the last step before ending the turn — mark the item `- [x]`. Add a `Notes:`
  sub-bullet if something surprising came up.
- Do not push to a remote. Do not run `gh pr create`. Do not edit `RALPH/specs/` or the prompt templates.
