#!/usr/bin/env bash
# Installs talosctl (matching Talos version) and kubectl into ~/.local/bin.
set -euo pipefail

TALOS_VERSION="${1:-1.7.6}"
KUBECTL_VERSION="${2:-v1.30.4}"

mkdir -p "$HOME/.local/bin"

echo "Installing talosctl v${TALOS_VERSION}..."
curl -fL --retry 3 -o "$HOME/.local/bin/talosctl" \
  "https://github.com/siderolabs/talos/releases/download/v${TALOS_VERSION}/talosctl-linux-amd64"
chmod +x "$HOME/.local/bin/talosctl"

echo "Installing kubectl ${KUBECTL_VERSION}..."
curl -fL --retry 3 -o "$HOME/.local/bin/kubectl" \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x "$HOME/.local/bin/kubectl"

"$HOME/.local/bin/talosctl" version --short 2>/dev/null || "$HOME/.local/bin/talosctl" version | head -2
"$HOME/.local/bin/kubectl" version --client --short 2>/dev/null || "$HOME/.local/bin/kubectl" version --client
