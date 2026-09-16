output "machine_secrets" {
  description = "Generated Talos machine secrets (import these to reuse the cluster CA)."
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "control_plane_machine_configs" {
  description = "Generated machine configuration per control plane node."
  value = {
    for name, cfg in data.talos_machine_configuration.control_plane :
    name => nonsensitive(cfg.id)
  }
}

output "talosconfig" {
  description = "Generated talos client configuration."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "talosconfig_path" {
  description = "Path to the generated talosconfig file."
  value       = local_file.talosconfig.filename
}

output "boot_assets" {
  description = "Kernel and initramfs URLs downloaded for matchbox."
  value = {
    kernel = local.kernel_url
    initrd = local.initrd_url
  }
}

output "matchbox_dir" {
  description = "Directory to mount into the matchbox container (/var/lib/matchbox)."
  value       = abspath(var.build_dir)
}

output "bootstrap_done" {
  description = "Whether etcd has been bootstrapped by this run."
  value       = var.bootstrap
}

output "kubernetes_version" {
  description = "Kubernetes version the cluster runs (drives talos_cluster upgrades)."
  value       = nonsensitive(local.kubernetes_version)
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig (written when bootstrap=true)."
  value       = "${var.build_dir}/kubeconfig"
}

output "next_steps" {
  description = "What to do after the first apply."
  value = join("\n", [
    "1. Start matchbox (or use -var manage_matchbox=true):",
    "   docker run -d --net=host --rm -v ${abspath(var.build_dir)}:/var/lib/matchbox:Z quay.io/poseidon/matchbox:v0.10.0 -address=0.0.0.0:8080 -log-level=debug",
    "2. PXE boot the first control plane node (${local.first_cp.name} / ${local.first_cp.ip}).",
    "3. Re-run: terraform apply -var bootstrap=true",
    "   (bootstraps etcd, waits for health, writes ${var.build_dir}/kubeconfig)",
    "4. PXE boot remaining control plane nodes and workers.",
    "5. Upgrade Kubernetes later by setting kubernetes_version and re-running with -var bootstrap=true.",
  ])
}
