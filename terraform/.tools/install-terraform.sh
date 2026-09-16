#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/bin"
curl -fLo /tmp/tf.zip https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
python3 - <<'PY'
import zipfile, os
d = os.path.expanduser("~/.local/bin")
with zipfile.ZipFile("/tmp/tf.zip") as z:
    z.extractall(d)
os.chmod(os.path.join(d, "terraform"), 0o755)
PY
"$HOME/.local/bin/terraform" version
