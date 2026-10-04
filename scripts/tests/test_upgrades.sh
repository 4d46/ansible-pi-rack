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

# --- review (the deterministic parts; the model is never called) -----------

# Fixtures: the real Renovate PR #13 (ES 8.19.22 → 9.5.4) and its diff; live
# facts seeded with made-up hostnames/addresses; a PR whose release notes try
# to break out of their section; and a Dependabot PR.
payload() {
    UPGRADES_PR_JSON=$fixtures/$1.json UPGRADES_PR_DIFF=$fixtures/${2:-$1}.diff \
        UPGRADES_FACTS_FILE=$fixtures/facts-with-hosts.txt UPGRADES_REDACT_HOSTS="pi-alpha pi-beta" \
        scripts/upgrades review 1 --dry-run 2>/dev/null
}
section() { sed -n "/^<$1/,/^<\/$1>/p" | sed '1d;$d'; }

check "review parses the upgrade from a real Renovate PR" \
    'package: docker.elastic.co/elasticsearch/elasticsearch
change: 8.19.22 → 9.5.4 (major update)
pull request: #13 "Update docker.elastic.co/elasticsearch/elasticsearch Docker tag to v9", opened by renovate, open' \
    "$(payload pr-13 | section upgrade)"

notes=$(payload pr-13 | section release_notes)
# shellcheck disable=SC2016  # the backticks are literal Markdown in Renovate's notes
check "review keeps the release notes but not Renovate's footer" \
    "first=yes footer=no debug=no" \
    "first=$(grep -q '^### \[`v9.5.4`\]' <<<"$notes" && echo yes || echo no) footer=$(grep -q '### Configuration' <<<"$notes" && echo yes || echo no) debug=$(grep -q 'renovate-debug' <<<"$notes" && echo yes || echo no)"

context=$(payload pr-13 | section deployment_context)
check "review includes the image's pin and the role that deploys it" \
    "pin=yes template=yes" \
    "pin=$(grep -q '^es_image_tag:' <<<"$context" && echo yes || echo no) template=$(grep -q '^=== roles/elasticsearch/templates/docker-compose.yml.j2 ===$' <<<"$context" && echo yes || echo no)"

# Exact output, so this fails on a leak (under-redaction) and on mangled
# neighbouring words (over-redaction) alike.
check "review redacts hostnames, FQDNs, tailnet names and IPs from live facts" \
    '--- container.sh ---
{
 "container": "elasticsearch",
 "image": "docker.elastic.co/elasticsearch/elasticsearch:8.19.22@sha256:e98f9c3b09be",
 "network_mode": "host"
}
--- elasticsearch.sh ---
Collector failed: Failed to connect to <host> port 22 (<host>, <ip>)
writer seen from <host> via <host>; subnet route <ip>
unrelated words must survive: alphabet, pi-alphabet, pi-beta-tools, version 8.19.22' \
    "$(payload pr-13 | section live_facts)"

injected=$(payload pr-injection pr-13)
check "review stops release notes closing their section or faking facts" \
    "closing_tags=1 facts_sections=1 defused=yes" \
    "closing_tags=$(grep -c '^</release_notes>$' <<<"$injected") facts_sections=$(grep -cE '^<live_facts( |>)' <<<"$injected") defused=$(grep -q '</release_notes-quoted>' <<<"$injected" && echo yes || echo no)"

check "review parses a Dependabot PR from its title" \
    'package: actions/checkout
change: 4 → 5
pull request: #21 "Bump actions/checkout from 4 to 5", opened by dependabot, open' \
    "$(payload pr-dependabot | section upgrade)"

scripts/upgrades review --dry-run >/dev/null 2>&1
check "review without a PR number exits 2" "2" "$?"

check "review schema is valid JSON and requires every field" \
    "true" \
    "$(jq '(.required | sort) == (.properties | keys | sort)' scripts/review/schema.json 2>&1)"

if ((failures > 0)); then
    echo "$failures test(s) failed"
    exit 1
fi
echo "all tests passed"
