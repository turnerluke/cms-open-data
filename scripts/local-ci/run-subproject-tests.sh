#!/usr/bin/env bash
# run-subproject-tests.sh — run `pytest` in every uv workspace member
# that has a `tests/` directory.
#
# Mirrors CI's `Test Subprojects` job from .github/workflows/test.yml so
# repo-standard pyproject failures (missing coverage config, missing
# 80% gate, etc.) surface locally before push instead of in CI.
#
# The list of members is read from the root pyproject.toml's
# `[tool.uv.workspace].members` array so adding a new workspace member
# requires no edits here.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/../.." && pwd)"
cd "$root_dir"

if [[ ! -f pyproject.toml ]]; then
    echo "run-subproject-tests.sh: no pyproject.toml at $root_dir" >&2
    exit 2
fi

rc=0
while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    if [[ ! -d "$member/tests" ]]; then
        echo "--- skip $member (no tests/) ---"
        continue
    fi
    echo "--- pytest in $member ---"
    if ! (cd "$member" && uv run pytest); then
        rc=1
    fi
done < <(
    uv run python -c "
import tomllib, pathlib
data = tomllib.loads(pathlib.Path('pyproject.toml').read_text())
for m in data['tool']['uv']['workspace']['members']:
    print(m)
"
)
exit "$rc"
