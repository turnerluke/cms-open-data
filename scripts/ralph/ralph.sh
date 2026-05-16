#!/usr/bin/env bash
# ralph.sh — Ralph Wiggum loop driver for the cms-open-data worktree
# container. See scripts/ralph/README.md for usage and rationale.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ralph.sh --mode plan|build [options] --ack-billing-cap

Required:
  --mode plan|build         Which prompt template to feed each iteration.
  --ack-billing-cap         Operator attests "extra usage" is OFF in
                            Anthropic billing settings (the only true
                            hard cap on overage). Refuses to start
                            without this flag.

Options:
  --max-iterations N        Stop after N iterations.    [default: 30]
  --per-iter-timeout DUR    timeout(1) duration string. [default: 15m]
  --model MODEL             Claude model identifier.    [default: claude-sonnet-4-6]
  --sentinel TOKEN          Completion phrase Ralph emits inside
                            <promise>...</promise> tags.  [default: RALPH_DONE]
  -h, --help                Print this help and exit.

Must be run from inside a sibling worktree of main (not main itself).
Reads RALPH/PROMPT_<mode>.md; appends a log to RALPH/ralph.log.
EOF
}

MODE=""
MAX_ITER=30
PER_ITER_TIMEOUT=15m
MODEL=claude-sonnet-4-6
SENTINEL=RALPH_DONE
ACK_CAP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --max-iterations)
            MAX_ITER="${2:-}"
            shift 2
            ;;
        --per-iter-timeout)
            PER_ITER_TIMEOUT="${2:-}"
            shift 2
            ;;
        --model)
            MODEL="${2:-}"
            shift 2
            ;;
        --sentinel)
            SENTINEL="${2:-}"
            shift 2
            ;;
        --ack-billing-cap)
            ACK_CAP=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'unknown flag: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$MODE" != "plan" && "$MODE" != "build" ]]; then
    echo "--mode must be plan or build" >&2
    exit 2
fi

if [[ "$ACK_CAP" -ne 1 ]]; then
    cat >&2 <<'EOF'
refusing to start: --ack-billing-cap not passed.

Before re-running, confirm "extra usage" is DISABLED in your Anthropic
account billing settings. With it off, Agent SDK requests fail-stop
when your monthly credit is exhausted, which is the only true overage
cap.

Then re-run with --ack-billing-cap.
EOF
    exit 2
fi

if ! [[ "$MAX_ITER" =~ ^[0-9]+$ ]] || [[ "$MAX_ITER" -lt 1 ]]; then
    echo "--max-iterations must be a positive integer (got: $MAX_ITER)" >&2
    exit 2
fi

if ! command -v claude > /dev/null 2>&1; then
    echo "claude CLI not found in PATH" >&2
    exit 127
fi

if ! command -v timeout > /dev/null 2>&1; then
    echo "timeout(1) not found in PATH (try: brew install coreutils)" >&2
    exit 127
fi

branch="$(git rev-parse --abbrev-ref HEAD 2> /dev/null || true)"
if [[ -z "$branch" ]]; then
    echo "not inside a git worktree" >&2
    exit 2
fi
if [[ "$branch" == "main" ]]; then
    echo "refusing to run on main; create a feature worktree via init.sh first" >&2
    exit 2
fi
if [[ ! -d RALPH ]]; then
    echo "no RALPH/ directory in $PWD; run init.sh from the container root first" >&2
    exit 2
fi

PROMPT_FILE="RALPH/PROMPT_${MODE}.md"
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "missing prompt template: $PROMPT_FILE" >&2
    exit 2
fi

mkdir -p RALPH/.state
LOG=RALPH/ralph.log
USAGE_LOG=RALPH/.state/usage.jsonl

have_jq=0
if command -v jq > /dev/null 2>&1; then
    have_jq=1
fi

iter_log="$(mktemp -t ralph-iter.XXXXXX)"
trap 'rm -f "$iter_log"' EXIT

{
    printf '\n==========================================================\n'
    printf 'ralph.sh: mode=%s model=%s max=%d timeout=%s branch=%s\n' \
        "$MODE" "$MODEL" "$MAX_ITER" "$PER_ITER_TIMEOUT" "$branch"
    printf 'started: %s\n' "$(date -Iseconds 2> /dev/null || date)"
    printf '==========================================================\n'
} | tee -a "$LOG"

stop_reason=max_iterations
prompt_body="$(cat "$PROMPT_FILE")"

for ((i = 1; i <= MAX_ITER; i++)); do
    printf '\n=== iter %d/%d (%s) ===\n' \
        "$i" "$MAX_ITER" "$(date -Iseconds 2> /dev/null || date)" \
        | tee -a "$LOG"

    : > "$iter_log"
    set +e
    timeout "$PER_ITER_TIMEOUT" \
        claude -p "$prompt_body" \
        --model "$MODEL" \
        --output-format stream-json \
        --verbose \
        --dangerously-skip-permissions \
        | tee "$iter_log"
    rc=${PIPESTATUS[0]}
    set -e

    cat "$iter_log" >> "$LOG"

    if [[ "$have_jq" -eq 1 ]]; then
        jq -c --argjson iter "$i" \
            'select(.type=="result") | {iter: $iter, usage: .usage, cost_usd: .total_cost_usd}' \
            "$iter_log" 2> /dev/null >> "$USAGE_LOG" || true
    fi

    if [[ "$rc" -ne 0 ]]; then
        printf 'claude returned non-zero exit (%d); stopping loop\n' "$rc" \
            | tee -a "$LOG"
        stop_reason="claude rc=$rc"
        break
    fi

    if grep -q "<promise>${SENTINEL}</promise>" "$iter_log"; then
        printf 'sentinel <promise>%s</promise> detected; stopping loop\n' \
            "$SENTINEL" | tee -a "$LOG"
        stop_reason=sentinel
        break
    fi
done

printf '\nfinished: %s (reason: %s)\n' \
    "$(date -Iseconds 2> /dev/null || date)" "$stop_reason" \
    | tee -a "$LOG"
