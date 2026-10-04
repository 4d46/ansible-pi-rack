#!/bin/sh
# Collector for 'upgrades review': Elasticsearch upgrade-readiness facts, as JSON.
# Runs on the Elasticsearch Pi via Ansible's script module. Read-only GETs
# against the local node, plus one aggregation query.
#
# Clients that write to Elasticsearch are summarised by agent type and version
# only. Agent names are hostnames, so they are never queried.
set -eu

ES=http://localhost:9200

get() { curl -sf "$ES$1"; }

{
    echo '{"root":'; get /
    echo ',"health":'; get /_cluster/health
    echo ',"deprecations":'; get /_migration/deprecations
    echo ',"system_features":'; get /_migration/system_features
    echo ',"index_versions":'; get '/_settings/index.version.created?flat_settings=true'
    echo ',"writers":'
    curl -sf "$ES/_all/_search" -H 'Content-Type: application/json' -d '{
        "size": 0,
        "query": {"range": {"@timestamp": {"gte": "now-24h"}}},
        "aggs": {"writers": {"multi_terms": {"terms": [
            {"field": "agent.type"}, {"field": "agent.version"}, {"field": "ecs.version"}]}}}
    }' || echo null
    echo '}'
} | python3 -c '
import json, sys

d = json.load(sys.stdin)
dep = d["deprecations"]
issues = []
for area, items in dep.items():
    if isinstance(items, dict):  # index-level: {index: [issues]}
        items = [i for lst in items.values() for i in lst]
    issues += [{"area": area, "level": i.get("level"), "message": i.get("message")} for i in items]
writers = (((d.get("writers") or {}).get("aggregations") or {}).get("writers") or {}).get("buckets", [])
print(json.dumps({
    "version": d["root"]["version"]["number"],
    "cluster_status": d["health"]["status"],
    "number_of_nodes": d["health"]["number_of_nodes"],
    "unassigned_shards": d["health"]["unassigned_shards"],
    "upgrade_deprecation_issues": issues,
    "system_feature_migration": d["system_features"]["migration_status"],
    "index_versions_created": sorted({s["settings"].get("index.version.created")
                                      for s in d["index_versions"].values()}),
    "writers_last_24h": [{"agent_type": b["key"][0], "agent_version": b["key"][1],
                          "ecs_version": b["key"][2], "docs": b["doc_count"]} for b in writers],
}, indent=1))
'
