# Ralph Wiggum loop toolkit

Autonomous AI coding loops for the `cms-open-data` worktree container,
following [Geoffrey Huntley's Ralph Wiggum technique][ralph].

[ralph]: https://ghuntley.com/ralph/

## Why this exists

One Ralph run = one feature worktree = one branch = one PR. The loop
runs `claude -p` headlessly against a stable prompt until a completion
sentinel fires or the iteration cap is reached. The existing pre-commit
`Stop` hook in `.claude/settings.json` provides backpressure between
iterations.

## Prerequisite (one-time, manual)

Disable **extra usage** in Anthropic account billing settings. With it
off, Agent SDK requests fail-stop when your monthly Agent SDK credit is
exhausted. This is the only true overage cap; the script-side flags
only bound a single run.

The `ralph.sh` script refuses to start without `--ack-billing-cap`,
which is an explicit attestation that you've done this.

## Usage

From the container root (`/Users/turner/projects/cms-open-data`):

```bash
# 1. Bootstrap a new feature worktree.
./main/scripts/ralph/init.sh add-my-feature
cd add-my-feature

# 2. Write specs by hand.
$EDITOR RALPH/specs/feature.md

# 3. Plan mode — generate IMPLEMENTATION_PLAN.md.
./scripts/ralph/ralph.sh --mode plan --max-iterations 3 \
    --model claude-haiku-4-5-20251001 --ack-billing-cap

# 4. Review and edit RALPH/IMPLEMENTATION_PLAN.md by hand.

# 5. Build mode — execute the plan.
./scripts/ralph/ralph.sh --mode build --max-iterations 30 \
    --model claude-sonnet-4-6 --ack-billing-cap

# 6. Review commits, push, open PR like any other branch.
git log main..HEAD
git push -u origin feat/add-my-feature
gh pr create
```

Monitor progress in another terminal:

```bash
tail -f add-my-feature/RALPH/ralph.log
```

Cancel an in-flight run with `Ctrl-C` (or `kill <pid>` if backgrounded).

## Files

| Path                        | Role                                                       |
| --------------------------- | ---------------------------------------------------------- |
| `init.sh`                   | Bootstraps a sibling worktree off main and seeds `RALPH/`. |
| `ralph.sh`                  | The loop driver.                                           |
| `templates/PROMPT_plan.md`  | Plan-mode prompt (gap analysis, writes the plan).          |
| `templates/PROMPT_build.md` | Build-mode prompt (executes one plan item per iteration).  |
| `templates/AGENTS_RALPH.md` | Operational crib sheet Ralph reads each iteration.         |

## Cost controls

| Layer             | Mechanism                                  | Cap                                          |
| ----------------- | ------------------------------------------ | -------------------------------------------- |
| Anthropic account | "Extra usage" toggle off                   | Hard fail-stop at monthly Agent SDK credit   |
| `ralph.sh` flag   | `--max-iterations` (default 30)            | Iterations per run                           |
| `ralph.sh` flag   | `--per-iter-timeout` (default 15m)         | Wall time per iteration                      |
| `ralph.sh` flag   | `--model` (default `claude-sonnet-4-6`)    | Order-of-magnitude per-iteration cost        |
| `ralph.sh` flag   | `--ack-billing-cap` (required)             | Forces operator to confirm account-level cap |
| Logging           | `RALPH/.state/usage.jsonl` (requires `jq`) | Post-run audit of token spend                |

Effective 2026-06-15, `claude -p` draws from a separate monthly Agent
SDK credit at full API rates (Pro $20, Max 5x $100, Max 20x $200),
distinct from interactive usage limits.

## How it composes with existing hooks

- `.claude/settings.json` `PostToolUse` hook keeps formatting Python on
  every edit. No change needed.
- `.claude/settings.json` `Stop` hook runs `uv run pre-commit run
--all-files` at the end of every iteration. Failures cause the
  iteration to exit non-zero; the next iteration sees the failure
  output in `RALPH/ralph.log` and fixes it. That is the backpressure
  mechanism — keep both hooks unchanged.

## Tear-down

After your feature PR merges:

```bash
git -C /Users/turner/projects/cms-open-data worktree remove add-my-feature
git -C /Users/turner/projects/cms-open-data/.bare branch -D feat/add-my-feature
```
