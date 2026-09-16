#!/usr/bin/env bash
# Post-bootstrap health gate: waits until all control plane nodes are Ready in
# Kubernetes and Talos services report healthy.
#
# Usage: health-check.sh <build_dir> <timeout_seconds> <cp_ip> [cp_ip...]
set -euo pipefail

BUILD_DIR="$1"
TIMEOUT="$2"
shift 2
CP_IPS=("$@")

TALOSCONFIG="$BUILD_DIR/talosconfig"
KUBECONFIG_FILE="$BUILD_DIR/kubeconfig"

[ -f "$TALOSCONFIG" ] || { echo "ERROR: $TALOSCONFIG not found" >&2; exit 1; }

deadline=$(( $(date +%s) + TIMEOUT ))

echo "Waiting for Talos services to be healthy on: ${CP_IPS[*]}"
for ip in "${CP_IPS[@]}"; do
  while true; do
    if talosctl --talosconfig "$TALOSCONFIG" -n "$ip" -e "$ip" health >/dev/null 2>&1; then
      echo "  $ip: Talos services healthy"
      break
    fi
    if [ "$(date +%s)" -gt "$deadline" ]; then
      echo "ERROR: Talos services on $ip not healthy within ${TIMEOUT}s" >&2
      exit 1
    fi
    sleep 15
  done
done

if [ -f "$KUBECONFIG_FILE" ]; then
  echo "Waiting for Kubernetes nodes to be Ready..."
  while true; do
    if KUBECONFIG="$KUBECONFIG_FILE" kubectl wait --for=condition=Ready node --all --timeout=30s >/dev/null 2>&1; then
      echo "All Kubernetes nodes are Ready."
      break
    fi
    if [ "$(date +%s)" -gt "$deadline" ]; then
      echo "ERROR: Kubernetes nodes not Ready within ${TIMEOUT}s" >&2
      exit 1
    fi
    sleep 15
  done
else
  echo "NOTE: kubeconfig not present yet; skipping Kubernetes Ready check."
fi

echo "Cluster health check passed."
