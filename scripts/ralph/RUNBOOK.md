# Ralph runbook

Step-by-step for running a Ralph loop in this repo. See `README.md` for
the why; this file is the how.

## One-time setup

1. In your Anthropic account billing settings, **disable "extra usage"**.
   This is the only true cap against overage once Agent SDK credits go
   live (2026-06-15). Everything else just bounds a single run.
2. Install `jq` (`brew install jq`) so per-iteration token usage gets
   logged to `RALPH/.state/usage.jsonl`.

## Per feature

### 1. Bootstrap a worktree

From the container root (`/Users/turner/projects/cms-open-data`):

```bash
./main/scripts/ralph/init.sh <feature-name>
cd <feature-name>
```

Creates `<feature-name>/` on `feat/<feature-name>` branched from the
current tip of `main`, seeded with prompt templates and an empty
`RALPH/specs/`.

### 2. Write specs

```bash
$EDITOR RALPH/specs/<thing>.md
```

One markdown file per concern. Be opinionated and concrete — Ralph
builds what the specs say, no more, no less. Include a clear
"Definition of done" section so the loop knows when to stop.

### 3. Plan mode (cheap, fast)

```bash
./scripts/ralph/ralph.sh \
    --mode plan \
    --max-iterations 3 \
    --model claude-haiku-4-5-20251001 \
    --ack-billing-cap
```

Generates `RALPH/IMPLEMENTATION_PLAN.md`. **Review and edit it by hand
before continuing** — this is the highest-leverage human checkpoint.
Cheaper to fix a bad plan than to pay Sonnet to execute one.

### 4. Build mode

```bash
./scripts/ralph/ralph.sh \
    --mode build \
    --max-iterations 25 \
    --model claude-sonnet-4-6 \
    --ack-billing-cap
```

In another terminal:

```bash
tail -f RALPH/ralph.log
```

The loop stops when:

- Ralph emits `<promise>RALPH_DONE</promise>` (every plan item `- [x]`).
- `--max-iterations` is reached.
- `claude` exits non-zero (most likely cause: Agent SDK credit exhausted).

Resume by re-running the same command — state lives on disk, so a
fresh iteration reads the partially-checked plan and continues.

### 5. Review and ship

```bash
git log main..HEAD --oneline
git diff main..HEAD
git push -u origin feat/<feature-name>
gh pr create --base main --fill
gh pr checks --watch
```

### 6. Tear down

After the PR merges:

```bash
cd /Users/turner/projects/cms-open-data
git -C main checkout main && git -C main pull --ff-only
git worktree remove <feature-name>
git -C .bare branch -D feat/<feature-name>
```

## Cancel mid-flight

`Ctrl-C` in the terminal running `ralph.sh`. State on disk persists; a
re-run picks up from the partially-checked plan.

## Cost expectations (rough)

| Mode  | Model  | Typical cost per run |
| ----- | ------ | -------------------- |
| plan  | Haiku  | $0.05–0.20           |
| build | Sonnet | $3–30                |

Audit a finished run:

```bash
jq -s 'map(.cost_usd) | add' RALPH/.state/usage.jsonl
```

## Common knobs to override

| Flag                 | When to bump                                                                |
| -------------------- | --------------------------------------------------------------------------- |
| `--model`            | Hand a single hard problem to Opus by editing the spec then re-running.     |
| `--max-iterations`   | Tight for first runs; widen once you trust the plan shape.                  |
| `--per-iter-timeout` | Default `15m`. Bump for assets that fetch real data; cut for pure refactor. |
| `--sentinel`         | Rarely needed. Useful if your prompt uses a different completion phrase.    |
