#!/usr/bin/env bash
# worktree-drop.sh — tear down a sibling worktree after its PR has merged.
#
# Mirrors worktree-new.sh: resolves the container root from the running
# worktree's git-common-dir, then runs the standard cleanup incantation:
#
#   1. detect the branch checked out in <name>/ (refuse `main`)
#   2. `git -C main pull --ff-only` so main is up-to-date with the squash
#      merge before the branch is deleted locally
#   3. `git worktree remove <name> --force`
#   4. `git branch -D <branch>` in the bare repo
#
# Step 4 uses `-D` (force) rather than `-d` because the repo squash-merges
# PRs, so feature branches never look "merged" from git's perspective
# even after the change has landed on main.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/worktree-drop.sh <name> [--force]

Removes the sibling worktree <name>/ from the bare-repo container and
force-deletes its branch from the bare repo. Refuses to run if:
  - <name> is `main`,
  - the worktree does not exist,
  - the worktree has uncommitted tracked changes (unless --force is
    passed; untracked build artifacts like .venv/ or evidence/build/ are
    always ignored).

Force-delete (`branch -D`) is intentional: PRs are squash-merged, so
git never sees a feature branch as merged into main even after it has
landed. `-d` would refuse every real-world cleanup.

Example:
  scripts/worktree-drop.sh nh-fines-chart
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 2
fi

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

name="$1"
force=0
if [[ $# -eq 2 ]]; then
    if [[ "$2" != "--force" ]]; then
        usage >&2
        exit 2
    fi
    force=1
fi

if [[ "$name" == "main" ]]; then
    echo "worktree-drop.sh: refusing to drop the main worktree" >&2
    exit 2
fi

common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
container="$(cd "$common_dir/.." && pwd)"

if [[ ! -d "$container/.bare" ]] || [[ ! -d "$container/main" ]]; then
    echo "worktree-drop.sh: $container does not look like a bare-repo worktree container" >&2
    exit 2
fi

target="$container/$name"
if [[ ! -d "$target" ]]; then
    echo "worktree-drop.sh: worktree does not exist: $target" >&2
    exit 2
fi

branch="$(git -C "$target" rev-parse --abbrev-ref HEAD)"
if [[ "$branch" == "main" ]] || [[ "$branch" == "HEAD" ]]; then
    echo "worktree-drop.sh: refusing to drop worktree on branch '$branch'" >&2
    exit 2
fi

# Only tracked-file changes count as "uncommitted work". `status --porcelain`
# without `-uall` still lists untracked entries, so filter them out — a
# freshly-built .venv/ or evidence/build/ is expected debris.
dirty="$(git -C "$target" status --porcelain | grep -Ev '^\?\?' || true)"
if [[ -n "$dirty" && "$force" -ne 1 ]]; then
    echo "worktree-drop.sh: $target has uncommitted tracked changes:" >&2
    echo "$dirty" >&2
    echo "re-run with --force to drop anyway" >&2
    exit 2
fi

echo "==> updating main"
git -C "$container/main" pull --ff-only

echo "==> removing worktree $target"
git -C "$container" worktree remove "$name" --force

echo "==> deleting branch $branch (force: squash-merge means -d would refuse)"
git -C "$container/.bare" branch -D "$branch"

echo
echo "dropped:"
echo "  path:   $target"
echo "  branch: $branch"
