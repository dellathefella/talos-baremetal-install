#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
cd /mnt/c/Users/jaked/Desktop/AITest/talos-baremetal-install/terraform

echo "=== terraform init ==="
terraform init -input=false -no-color

echo "=== terraform validate ==="
terraform validate -no-color

echo "=== terraform plan (defaults: matchbox/iPXE unmanaged) ==="
terraform plan -input=false -no-color -var-file=terraform.tfvars.example 2>&1 | tail -15
