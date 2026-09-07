#!/usr/bin/env bash
# worktree-new.sh — create a sibling worktree in the bare-repo container.
#
# The repo lives in a bare-repo worktree container:
#
#     <container>/.bare/       bare git repo
#     <container>/main/        worktree on `main`
#     <container>/<name>/      sibling worktrees for feature branches
#
# This script automates the four-step incantation a maintainer would
# otherwise run by hand for every branch:
#
#   1. `git worktree add`
#   2. seed data/raw/ from main/ so extractors don't re-download CMS files
#   3. `uv sync --all-packages --all-groups` inside the new worktree
#   4. `dbt deps` inside dbt/cms_analytics/ (uses the new venv's dbt)
#
# The container root is resolved from the running worktree's git-common-dir
# so this script works from any sibling worktree, not just main/.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/worktree-new.sh <name> [branch]

Creates a sibling worktree <name>/ next to main/ in the bare-repo
container, branched from the current tip of main. If <branch> is
omitted it defaults to feat/<name>, matching the container convention.

After the worktree is created the script also:
  - rsyncs main/data/raw/ into <name>/data/raw/ (if it exists) so
    dbt/Dagster don't re-download CMS extracts,
  - runs `uv sync --all-packages --all-groups` inside the new worktree,
  - runs `dbt deps` inside <name>/dbt/cms_analytics/ (if present).

Examples:
  scripts/worktree-new.sh nh-fines-chart
      # creates worktree nh-fines-chart/ on branch feat/nh-fines-chart

  scripts/worktree-new.sh nh-fines-chart fix/nh-fines-chart
      # creates worktree nh-fines-chart/ on branch fix/nh-fines-chart
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
branch="${2:-feat/$name}"

if ! [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "worktree-new.sh: name must be lowercase kebab/dot/underscore (got: $name)" >&2
    exit 2
fi

# Resolve the container root from the git-common-dir of whichever worktree
# invoked this script. `--git-common-dir` points at the shared `.bare/`
# (or `.git/` in a non-bare repo), so its parent is the container root.
common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
container="$(cd "$common_dir/.." && pwd)"

if [[ ! -d "$container/.bare" ]] || [[ ! -d "$container/main" ]]; then
    echo "worktree-new.sh: $container does not look like a bare-repo worktree container" >&2
    echo "  expected $container/.bare and $container/main to exist" >&2
    exit 2
fi

dest="$container/$name"
if [[ -e "$dest" ]]; then
    echo "worktree-new.sh: destination already exists: $dest" >&2
    exit 2
fi

echo "==> creating worktree $dest on branch $branch"
git -C "$container" worktree add "$dest" -b "$branch" main

if [[ -d "$container/main/data/raw" ]]; then
    echo "==> seeding data/raw/ from main/ (avoids re-downloading CMS extracts)"
    mkdir -p "$dest/data/raw"
    rsync -a "$container/main/data/raw/" "$dest/data/raw/"
else
    echo "==> skipping data/raw/ seed (main/data/raw/ does not exist)"
fi

echo "==> uv sync --all-packages --all-groups in $dest"
(
    cd "$dest"
    uv sync --all-packages --all-groups
)

if [[ -d "$dest/dbt/cms_analytics" ]]; then
    echo "==> dbt deps in $dest/dbt/cms_analytics"
    (
        cd "$dest/dbt/cms_analytics"
        # Put the worktree's own .venv/bin on PATH so `dbt` resolves to
        # the freshly synced interpreter rather than whatever venv the
        # caller happened to have activated.
        PATH="$dest/.venv/bin:$PATH" dbt deps
    )
else
    echo "==> skipping dbt deps (no dbt/cms_analytics dir)"
fi

echo
echo "worktree ready:"
echo "  path:   $dest"
echo "  branch: $branch"
