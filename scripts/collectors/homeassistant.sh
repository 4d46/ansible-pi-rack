#!/bin/sh
# Collector for 'upgrades review': which Home Assistant integrations are in use,
# as JSON, so a review can ignore changelog entries that don't apply.
# Runs on the Home Assistant Pi via Ansible's script module (read-only).
#
# Only integration domain names (e.g. "zha", "sonos") are read: never entry
# titles, device names, hosts or credentials, which live in the same file.
# Usage: homeassistant.sh <config-dir>
set -eu

config=$1
python3 - "$config" <<'EOF'
import json, sys

config = sys.argv[1]
with open(f"{config}/.storage/core.config_entries") as f:
    entries = json.load(f)["data"]["entries"]
with open(f"{config}/.HA_VERSION") as f:
    version = f.read().strip()
print(json.dumps({
    "version": version,
    "integrations_in_use": sorted({e["domain"] for e in entries}),
}, indent=1))
EOF
