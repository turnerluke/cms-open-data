#!/usr/bin/env bash
# smoke-test-site.sh — post-deploy sanity check for the Evidence site.
#
# Called by the `smoke_test` job in .github/workflows/warehouse.yml after
# actions/deploy-pages publishes the built site. Before this script a
# broken deploy (bad basePath, empty data, dropped route) would go
# unnoticed until a maintainer manually curled the site.
#
# For each known top-level page under evidence/pages/ the script:
#   1. asserts an HTTP 200 response (retrying with backoff, because the
#      GitHub Pages CDN can lag a few tens of seconds behind the deploy
#      job's completion event),
#   2. greps the returned HTML for a page-specific sentinel string
#      (the frontmatter title, which Evidence renders into both the
#      <title> tag and the <h1 class="title"> heading) so an empty
#      shell / SPA-fallback / wrong-page response fails loudly.
#
# The route/sentinel table below is kept in sync by hand with the
# evidence/pages/*.md files (six pages today, all shallow). Sentinels
# are the frontmatter `title:` values — stable across data refreshes,
# unlike any count/aggregate that would change week over week.
#
# Runnable locally against the live site:
#
#     bash scripts/smoke-test-site.sh https://turnerluke.github.io/cms-open-data
#
# Exit codes:
#   0  every route returned 200 with its sentinel present
#   1  at least one route failed status or sentinel after all retries
#   2  usage error

set -euo pipefail

# Retry tuning: 6 attempts with 5s → 30s exponential-ish backoff sums to
# ~105s per route, well under a CDN's typical propagation window while
# still bounding total runtime for six routes at a few minutes worst-case.
readonly MAX_ATTEMPTS=6
readonly BACKOFFS=(5 10 15 20 25 30)

# route<TAB>sentinel — keep in sync with evidence/pages/*.md frontmatter.
readonly ROUTES=(
    "/	CMS Open Data"
    "/cost-vs-quality/	Cost vs quality"
    "/drug-spending/	Drug spending"
    "/home-health-hospice/	Home health and hospice"
    "/hospital-quality/	Hospital quality"
    "/nursing-homes/	Nursing homes"
    "/prescribers/	Prescribers"
)

usage() {
    cat <<'EOF'
Usage: scripts/smoke-test-site.sh <base-url>

Verifies every top-level Evidence page on <base-url> returns HTTP 200
and contains its page-specific sentinel string. Retries each route up
to 6 times with backoff to absorb GitHub Pages CDN propagation delay.

<base-url> may be given with or without a trailing slash; e.g.

    scripts/smoke-test-site.sh https://turnerluke.github.io/cms-open-data

Exit codes:
  0  every route passed
  1  at least one route failed status or sentinel
  2  usage error
EOF
}

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 2
fi

case "${1}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

base_url="${1%/}"

if ! [[ "$base_url" =~ ^https?:// ]]; then
    echo "smoke-test-site.sh: <base-url> must start with http:// or https:// (got: $base_url)" >&2
    exit 2
fi

# Fetch one URL once. Emits `status<TAB>body-path` on success, empty on
# transport error. Body is captured to a temp file so we can grep it
# without buffering multi-hundred-KB HTML through a shell variable.
fetch_once() {
    local url="$1" body_path="$2" status
    if ! status="$(curl -sS -L -o "$body_path" -w '%{http_code}' \
        --max-time 30 --connect-timeout 10 \
        --user-agent 'cms-open-data-smoke-test/1' \
        "$url" 2>/dev/null)"; then
        return 1
    fi
    printf '%s\n' "$status"
}

# Check one route with retry/backoff. Returns 0 on pass, 1 on final fail.
# All progress lines go to stderr so a caller could redirect stdout for a
# machine-readable pass/fail line (none defined today, but the shape is
# ready if a future orchestrator wants one).
check_route() {
    local route="$1" sentinel="$2"
    local url="${base_url}${route}"
    local body_path status attempt=0

    body_path="$(mktemp -t smoke-test-body.XXXXXX)"
    # shellcheck disable=SC2064  # want the path expanded now, not at trap fire
    trap "rm -f '$body_path'" RETURN

    while (( attempt < MAX_ATTEMPTS )); do
        if status="$(fetch_once "$url" "$body_path")" && [[ "$status" == "200" ]]; then
            if grep -qF -- "$sentinel" "$body_path"; then
                echo "==> PASS $route (200, sentinel present)" >&2
                return 0
            fi
            echo "==> $route: 200 but sentinel '$sentinel' missing (attempt $((attempt + 1))/$MAX_ATTEMPTS)" >&2
        else
            echo "==> $route: status='${status:-transport-error}' (attempt $((attempt + 1))/$MAX_ATTEMPTS)" >&2
        fi

        if (( attempt < MAX_ATTEMPTS - 1 )); then
            sleep "${BACKOFFS[attempt]}"
        fi
        attempt=$((attempt + 1))
    done

    echo "==> FAIL $route after $MAX_ATTEMPTS attempts (last status='${status:-transport-error}')" >&2
    return 1
}

echo "==> smoke-testing $base_url (${#ROUTES[@]} routes)" >&2

failures=0
for entry in "${ROUTES[@]}"; do
    route="${entry%%$'\t'*}"
    sentinel="${entry#*$'\t'}"
    if ! check_route "$route" "$sentinel"; then
        failures=$((failures + 1))
    fi
done

if (( failures > 0 )); then
    echo "==> FAIL $failures/${#ROUTES[@]} route(s) broken" >&2
    exit 1
fi

echo "==> PASS all ${#ROUTES[@]} routes healthy" >&2
