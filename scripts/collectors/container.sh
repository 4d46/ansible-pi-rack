#!/bin/sh
# Collector for 'upgrades review': how a container is deployed, as JSON.
# Runs on a Pi via Ansible's script module (read-only: docker inspect only).
#
# Deliberately selects fields instead of dumping 'docker inspect', which also
# holds environment variables (secrets such as tokens and auth keys live there).
# Usage: container.sh <container-name>
set -eu

docker inspect "$1" | python3 -c '
import json, sys

c = json.load(sys.stdin)[0]
host = c["HostConfig"]
print(json.dumps({
    "container": c["Name"].lstrip("/"),
    "image": c["Config"]["Image"],
    "status": c["State"]["Status"],
    "health": (c["State"].get("Health") or {}).get("Status", "no healthcheck"),
    "started_at": c["State"]["StartedAt"],
    "restart_count": c["RestartCount"],
    "network_mode": host["NetworkMode"],
    "privileged": host["Privileged"],
    "cap_add": host.get("CapAdd") or [],
    "devices": [d["PathInContainer"] for d in host.get("Devices") or []],
    "memory_limit_bytes": host.get("Memory") or None,
    "published_ports": sorted((c["NetworkSettings"].get("Ports") or {}).keys()),
    "mounts": [{"destination": m["Destination"], "type": m["Type"], "read_only": not m["RW"]}
               for m in c["Mounts"]],
    "env_var_names": sorted(e.split("=", 1)[0] for e in c["Config"].get("Env") or []),
}, indent=1))
'
