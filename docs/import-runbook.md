# Import runbook: adopting an existing Talos cluster

This brings a cluster that was created manually (e.g. via `talosctl gen config`)
under this Terraform module's management without recreating it.

## Prerequisite: the original secrets file

Terraform must control the exact CA/key material the cluster already runs.
That means you need the **original `secrets.yaml`** produced by
`talosctl gen secrets` when the cluster was created.

- If you have it: proceed. Keep it `0600` and back it up off-box.
- If you lost it: the cluster keeps running, but it **cannot** be adopted —
  regenerating secrets would produce a different CA and break every existing
  certificate. Plan a rebuild instead.

## Steps

Run from WSL/Linux with a `talosctl` whose version matches the cluster's Talos
version exactly.

1. Describe the running cluster in tfvars — every value must match reality:

   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # set cluster_name, cluster_endpoint, vip, gateway, cidr_prefix,
   # talos_version, install_disk, factory_schematic_id,
   # and control_plane_nodes (name/mac/ip) exactly as the cluster runs
   ```

2. Initialize and import the secrets:

   ```bash
   terraform init
   terraform import talos_machine_secrets.this /path/to/secrets.yaml
   ```

3. If the cluster is already bootstrapped, record that too (the resource is
   gated by `bootstrap=true`, so pass the var during import):

   ```bash
   terraform import -var bootstrap=true 'talos_machine_bootstrap.this[0]' talos-cluster
   ```

4. Review the plan carefully:

   ```bash
   terraform plan -var bootstrap=true
   ```

   Expected:
   - `talos_machine_secrets` and `talos_machine_bootstrap` are **unchanged**.
   - matchbox `assets/`, `groups/`, `profiles/` are regenerated (content
     should match what matchbox already serves).
   - `null_resource.health_check` / `null_resource.kubeconfig` are added —
     they just re-run checks and rewrite `build/kubeconfig` (harmless).

   **Not expected:** any diff on `talos_machine_configuration` or
   `talos_machine_configuration_apply`. If you see one, your tfvars do not
   match the running cluster — fix them before applying. Never apply a plan
   that changes the CA or node networking.

5. Take over management:

   ```bash
   terraform apply -var bootstrap=true
   ```

6. From here on, use the normal staged flow (`make bootstrap`, `make drift`,
   `make upgrade`-style runs, etc.).

## Verifying after import

```bash
talosctl --talosconfig build/talosconfig health
KUBECONFIG=build/kubeconfig kubectl get nodes -o wide
```

Both should report healthy/Ready with the same node names and IPs you put in
tfvars.
