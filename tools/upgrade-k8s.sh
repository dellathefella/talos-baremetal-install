#!/usr/bin/env bash
# Controlled Kubernetes upgrade using Talos's native upgrade-k8s procedure:
# pre-pulls images and upgrades apiserver/controller-manager/scheduler/kube-proxy
# and kubelets sequentially with health gating.
#
# Usage: upgrade-k8s.sh <build_dir> <target_version> <cp_ip> [cp_ip...]
#   e.g. upgrade-k8s.sh terraform/build v1.30.4 10.10.1.200
set -euo pipefail

BUILD_DIR="$1"
TARGET="$2"
shift 2
CP_IPS=("$@")

TALOSCONFIG="$BUILD_DIR/talosconfig"
FIRST_CP="${CP_IPS[0]}"

[ -f "$TALOSCONFIG" ] || { echo "ERROR: $TALOSCONFIG not found" >&2; exit 1; }

echo "Upgrading Kubernetes to $TARGET via $FIRST_CP (this can take a while)..."
talosctl --talosconfig "$TALOSCONFIG" -n "$FIRST_CP" -e "$FIRST_CP" \
  upgrade-k8s --to "$TARGET"

echo "Upgrade finished. Current node versions:"
KUBECONFIG="$BUILD_DIR/kubeconfig" kubectl get nodes -o wide
