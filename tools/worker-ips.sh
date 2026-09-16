#!/usr/bin/env bash
# Discovers worker node InternalIPs from the running cluster and prints them as a
# JSON map { "<name>": "<ip>" } for use with data.external.
#
# Usage: worker-ips.sh <build_dir>
# Requires: kubectl and a kubeconfig at <build_dir>/kubeconfig
set -euo pipefail

BUILD_DIR="$1"
KUBECONFIG_FILE="$BUILD_DIR/kubeconfig"

if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "ERROR: $KUBECONFIG_FILE not found. Run with bootstrap=true first." >&2
  exit 1
fi

KUBECONFIG="$KUBECONFIG_FILE" kubectl get nodes -o json | python3 -c '
import json, sys

data = json.load(sys.stdin)
workers = {}
for node in data.get("items", []):
    labels = node.get("metadata", {}).get("labels", {})
    if "node-role.kubernetes.io/control-plane" in labels:
        continue
    name = node["metadata"]["name"]
    ip = next(
        (a["address"] for a in node.get("status", {}).get("addresses", [])
         if a.get("type") == "InternalIP"),
        None,
    )
    if ip:
        workers[name] = ip

print(json.dumps(workers))
'
