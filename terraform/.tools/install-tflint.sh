#!/usr/bin/env bash
set -euo pipefail
cd /tmp
curl -fsSLO https://github.com/terraform-linters/tflint/releases/latest/download/tflint_linux_amd64.zip
python3 - <<'PY'
import zipfile, os
with zipfile.ZipFile("/tmp/tflint_linux_amd64.zip") as z:
    z.extractall(os.path.expanduser("~/.local/bin"))
PY
chmod +x ~/.local/bin/tflint
TFDIR=/mnt/c/Users/jaked/Desktop/AITest/talos-baremetal-install/terraform
~/.local/bin/tflint --init --chdir="$TFDIR"
~/.local/bin/tflint --chdir="$TFDIR"
echo "TFLINT_CLEAN"
