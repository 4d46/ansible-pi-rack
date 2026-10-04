#!/usr/bin/env bash
# Tests for scripts/upgrades. The fixtures are real 'gh pr list --json' responses
# for this repo's Renovate PRs (bodies trimmed to the version table), plus edge
# cases: failing and running CI, a conflicting PR, a Dependabot PR and a human
# PR. If Renovate or Dependabot change their PR format, these break before the
# list quietly starts showing "? → ?".
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
fixtures=scripts/tests/fixtures
failures=0

check() {
    local name=$1 expected=$2 actual=$3
    if [[ "$expected" == "$actual" ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/     /'
        failures=$((failures + 1))
    fi
}

# Every Renovate/Dependabot row parsed from real PR bodies and titles, human PR excluded.
check "list parses real PR responses" \
    "$(cat "$fixtures/open-prs.expected")" \
    "$(UPGRADES_PRS_JSON=$fixtures/open-prs.json scripts/upgrades list)"

check "list has no row for the human PR" \
    "" \
    "$(UPGRADES_PRS_JSON=$fixtures/open-prs.json scripts/upgrades list | grep '^#20 ' || true)"

check "list with nothing open says so" \
    "No open dependency PRs." \
    "$(UPGRADES_PRS_JSON=$fixtures/no-prs.json scripts/upgrades list)"

# Columns line up: the last column ("opened ...") starts at the same character
# offset on every row. ${#var} counts characters (not bytes) in a UTF-8 locale,
# which matters because rows contain → ✓ ✗ ….
utf8_locale=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.utf-?8$' | head -1)
check "list columns align" \
    "1" \
    "$(UPGRADES_PRS_JSON=$fixtures/open-prs.json scripts/upgrades list \
        | LC_ALL=${utf8_locale:-C.UTF-8} bash -c 'while IFS= read -r line; do prefix=${line%%opened*}; echo "${#prefix}"; done' \
        | sort -u | wc -l | tr -d ' ')"

scripts/upgrades nonsense >/dev/null 2>&1
check "unknown command exits 2" "2" "$?"

scripts/upgrades help >/dev/null 2>&1
check "help exits 0" "0" "$?"

if ((failures > 0)); then
    echo "$failures test(s) failed"
    exit 1
fi
echo "all tests passed"
