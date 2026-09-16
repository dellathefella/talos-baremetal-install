#!/usr/bin/env bash
# Replace/reset a Talos node: wipes STATE + EPHEMERAL, reboots, then waits for
# the node to rejoin the cluster after it has been re-PXE booted.
#
# Usage: replace-node.sh <node_ip> [api_node_ip]
#   node_ip      the node to reset
#   api_node_ip  a healthy node to talk to (defaults to node_ip)
#
# Env:
#   BUILD_DIR  dir containing talosconfig/kubeconfig (default: ../terraform/build)
#   YES=true   skip the interactive confirmation
#   TIMEOUT  seconds to wait for rejoin (default 900)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/../terraform/build}"
NODE_IP="${1:?usage: replace-node.sh <node_ip> [api_node_ip]}"
API_IP="${2:-$NODE_IP}"
YES="${YES:-}"
TIMEOUT="${TIMEOUT:-900}"

TALOSCONFIG="$BUILD_DIR/talosconfig"
KUBECONFIG_FILE="$BUILD_DIR/kubeconfig"

[ -f "$TALOSCONFIG" ] || { echo "ERROR: $TALOSCONFIG not found" >&2; exit 1; }
[ -f "$KUBECONFIG_FILE" ] || { echo "ERROR: $KUBECONFIG_FILE not found" >&2; exit 1; }

echo "WARNING: this will WIPE STATE and EPHEMERAL on node $NODE_IP and reboot it."
echo "The node must be re-PXE booted (iPXE USB) to rejoin the cluster."
if [ "$YES" != "true" ]; then
  read -r -p "Type the node IP to confirm: " confirm
  [ "$confirm" = "$NODE_IP" ] || { echo "Aborted (confirmation did not match)." >&2; exit 1; }
fi

echo "Resetting $NODE_IP via $API_IP ..."
talosctl --talosconfig "$TALOSCONFIG" -n "$NODE_IP" -e "$API_IP" \
  reset --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --reboot

echo "Node reset. PXE-boot it now. Waiting up to ${TIMEOUT}s for it to rejoin as Ready..."
deadline=$(( $(date +%s) + TIMEOUT ))
while true; do
  if KUBECONFIG="$KUBECONFIG_FILE" kubectl get nodes -o wide --no-headers 2>/dev/null \
    | awk -v ip="$NODE_IP" '$6 == ip && $2 ~ /Ready/ { found = 1 } END { exit !found }'; then
    echo "Node $NODE_IP rejoined and is Ready."
    exit 0
  fi
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo "ERROR: timed out waiting for $NODE_IP to rejoin." >&2
    exit 1
  fi
  sleep 15
done
