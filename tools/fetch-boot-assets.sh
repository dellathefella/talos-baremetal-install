#!/usr/bin/env bash
# Downloads Talos boot assets (kernel + initramfs) into the matchbox assets dir
# and optionally verifies SHA256 checksums.
#
# Usage: fetch-boot-assets.sh <out_dir> <kernel_url> <initrd_url> [kernel_sha256] [initrd_sha256]
set -euo pipefail

OUT_DIR="$1"
KERNEL_URL="$2"
INITRD_URL="$3"
KERNEL_SHA="${4:-}"
INITRD_SHA="${5:-}"

mkdir -p "$OUT_DIR"

verify() {
  local file="$1" expected="$2" label="$3"
  if [ -z "$expected" ]; then
    return 0
  fi
  local actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: $label checksum mismatch" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    rm -f "$file"
    exit 1
  fi
  echo "$label checksum OK ($actual)"
}

echo "Downloading kernel: $KERNEL_URL"
curl -fL --retry 3 -o "$OUT_DIR/vmlinuz" "$KERNEL_URL"
verify "$OUT_DIR/vmlinuz" "$KERNEL_SHA" "kernel"

echo "Downloading initramfs: $INITRD_URL"
curl -fL --retry 3 -o "$OUT_DIR/initramfs.xz" "$INITRD_URL"
verify "$OUT_DIR/initramfs.xz" "$INITRD_SHA" "initramfs"

echo "Boot assets ready in $OUT_DIR"
