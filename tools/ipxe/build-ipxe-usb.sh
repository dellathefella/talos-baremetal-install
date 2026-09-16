#!/usr/bin/env bash
# Builds terraform/build/ipxe.usb (BIOS + UEFI) with the Terraform-generated
# boot.ipxe chain script embedded. Requires Docker.
#
# Run from anywhere:
#   ./tools/ipxe/build-ipxe-usb.sh
#
# Override inputs:
#   BOOT_IPXE=/path/to/boot.ipxe OUT=/path/to/out ./tools/ipxe/build-ipxe-usb.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOT_IPXE="${BOOT_IPXE:-$REPO_ROOT/terraform/build/boot.ipxe}"
OUT="${OUT:-$REPO_ROOT/terraform/build}"

if [ ! -f "$BOOT_IPXE" ]; then
  echo "ERROR: $BOOT_IPXE not found. Run 'terraform apply' in terraform/ first." >&2
  exit 1
fi

mkdir -p "$OUT"

docker build \
  -f "$REPO_ROOT/tools/ipxe/Dockerfile" \
  --build-arg "IPXE_REPO=${IPXE_REPO:-https://github.com/ipxe/ipxe.git}" \
  --build-arg "IPXE_REF=${IPXE_REF:-master}" \
  --output "type=local,dest=$OUT" \
  "$REPO_ROOT"

echo "Wrote $OUT/ipxe.usb"
echo "Flash it: sudo dd if=$OUT/ipxe.usb of=/dev/sdX bs=4M status=progress conv=fsync"
echo "     or:  etcher $OUT/ipxe.usb"
