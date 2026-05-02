# Project Conventions

## Git Workflow

- **Always work on a branch.** Never commit directly to `main`.
- **Always open a PR** for changes — even trivial ones. No direct pushes to
  `main`.
- Use conventional-commit format for commit messages and PR titles
  (`feat:`, `fix:`, `docs:`, `chore:`, etc.).
- Keep each PR focused on one logical change.
- **Never add co-author trailers** to commits (no `Co-Authored-By:` lines —
  including for Claude). Commits should be authored solely by the user.

## After Opening a PR

- **Do not stop the turn until CI is green.** After `gh pr create`, poll
  `gh pr checks <num>` until every check has finished. If any check fails,
  pull the failure detail (e.g. PR comments via
  `gh api repos/<owner>/<repo>/issues/<num>/comments`), fix the issue, push,
  and re-poll. Only report the PR as done when all required checks pass.
- Prefer `ScheduleWakeup` over tight polling so the conversation context
  isn't burned waiting on the runner.

## Linting

- Pre-commit is installed. Run `uv run pre-commit run --all-files` to
  reproduce CI locally.
- A Stop hook runs `pre-commit run --all-files` automatically — Claude
  cannot end a turn while linters are unhappy.
- A PostToolUse hook runs `ruff format` + `ruff check --fix` on any
  `.py` file just edited.
