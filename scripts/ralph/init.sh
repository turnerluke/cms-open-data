#!/usr/bin/env bash
# init.sh — bootstrap a new Ralph worktree off main.
# See scripts/ralph/README.md for usage and rationale.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/ralph/init.sh <name>

Creates a sibling worktree <name>/ on branch feat/<name>, branched from
the current tip of main, and seeds <name>/RALPH/ with prompt templates.

<name> must be lowercase kebab-case (e.g. add-foo-thing).

Safe to run from either the container root or the main/ worktree.
EOF
}

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 2
fi

name="$1"
case "$name" in
    -h | --help)
        usage
        exit 0
        ;;
esac

if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "name must be lowercase kebab-case (got: $name)" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
templates_dir="$script_dir/templates"

# scripts/ralph lives inside the main/ worktree:
#   <container>/main/scripts/ralph
# so the container root is three levels up from script_dir.
container="$(cd "$script_dir/../../.." && pwd)"

if [[ ! -d "$container/main" ]] || [[ ! -d "$container/.bare" ]]; then
    echo "expected $container to be a bare-repo worktree container" >&2
    exit 2
fi

dest="$container/$name"
if [[ -e "$dest" ]]; then
    echo "destination already exists: $dest" >&2
    exit 2
fi

echo "==> updating main"
git -C "$container/main" checkout main
git -C "$container/main" pull --ff-only

echo "==> creating worktree $dest on branch feat/$name"
git -C "$container" worktree add "$dest" -b "feat/$name" main

echo "==> seeding $dest/RALPH/"
mkdir -p "$dest/RALPH/specs"
cp "$templates_dir/PROMPT_plan.md" "$dest/RALPH/PROMPT_plan.md"
cp "$templates_dir/PROMPT_build.md" "$dest/RALPH/PROMPT_build.md"
cp "$templates_dir/AGENTS_RALPH.md" "$dest/RALPH/AGENTS_RALPH.md"

cat <<EOF

ralph worktree ready
  path:   $dest
  branch: feat/$name

next steps:
  1. cd $dest
  2. write one or more specs into RALPH/specs/*.md
  3. plan mode (cheap, short):
       ./scripts/ralph/ralph.sh --mode plan --max-iterations 3 \\
         --model claude-haiku-4-5-20251001 --ack-billing-cap
  4. review RALPH/IMPLEMENTATION_PLAN.md by hand; edit if needed
  5. build mode:
       ./scripts/ralph/ralph.sh --mode build --max-iterations 30 \\
         --model claude-sonnet-4-6 --ack-billing-cap
  6. review commits, push, open PR like any other branch

cost cap reminder: confirm "extra usage" is DISABLED in Anthropic
billing settings before passing --ack-billing-cap.
EOF
