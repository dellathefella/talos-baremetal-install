#!/usr/bin/env bash
# Reports the talosctl client version as JSON for use with data.external.
# Never exits non-zero so Terraform can surface the mismatch via a precondition.
#
# Usage: check-talosctl-version.sh <expected_tag>   e.g. v1.7.6
set -uo pipefail

EXPECTED="${1:?usage: check-talosctl-version.sh <expected_tag>}"
BIN="${TALOSCTL:-talosctl}"

if ! command -v "$BIN" >/dev/null 2>&1; then
  printf '{"client": "missing", "expected": "%s", "match": "false"}\n' "$EXPECTED"
  exit 0
fi

CLIENT="$("$BIN" version -o json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["client"]["tag"])' 2>/dev/null || echo unknown)"

if [ "$CLIENT" = "$EXPECTED" ]; then
  MATCH="true"
else
  MATCH="false"
fi

printf '{"client": "%s", "expected": "%s", "match": "%s"}\n' "$CLIENT" "$EXPECTED" "$MATCH"
