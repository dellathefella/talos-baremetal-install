# ---------------------------------------------------------------------------
# Talos bare metal automation
#
# Stage 1 (no nodes required):
#   terraform apply
#     -> generates machine configs, matchbox groups/profiles, boot assets,
#        talosconfig and boot.ipxe under ${build_dir}/
#
# Stage 2 (after the first control plane node has PXE booted):
#   terraform apply -var bootstrap=true
#     -> bootstraps etcd on the first control plane node
#
# Stage 3 (optional, for config drift on running nodes):
#   terraform apply -var apply_to_running_nodes=true
# ---------------------------------------------------------------------------

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"

  lifecycle {
    precondition {
      condition     = length(var.control_plane_nodes) > 0 && length(var.control_plane_nodes) % 2 == 1
      error_message = "control_plane_nodes must be non-empty and odd (1, 3, 5...) for etcd quorum."
    }

    precondition {
      condition     = length(distinct([for n in var.control_plane_nodes : n.mac])) == length(var.control_plane_nodes)
      error_message = "Control plane MAC addresses must be unique."
    }

    precondition {
      condition     = length(distinct([for n in var.control_plane_nodes : n.ip])) == length(var.control_plane_nodes)
      error_message = "Control plane IPs must be unique."
    }

    precondition {
      condition     = alltrue([for n in var.control_plane_nodes : can(cidrhost("0.0.0.0/32", 0)) && n.ip != ""])
      error_message = "Every control plane node must have a non-empty ip."
    }

    precondition {
      condition     = can(cidrhost("10.0.0.0${var.cidr_prefix}", 0))
      error_message = "cidr_prefix must be a valid CIDR prefix (e.g. /16)."
    }

    precondition {
      condition     = regex("//([^:/]+)", var.cluster_endpoint)[0] == var.vip || regex("//([^:/]+)", var.cluster_endpoint)[0] == try(var.control_plane_nodes[0].ip, "")
      error_message = "cluster_endpoint host must equal the VIP or the first control plane node IP."
    }

    precondition {
      condition     = length(distinct(concat([for n in var.control_plane_nodes : n.mac], [for n in var.worker_nodes : n.mac if n.mac != null]))) == length(var.control_plane_nodes) + length([for n in var.worker_nodes : n.mac if n.mac != null])
      error_message = "MAC addresses must be unique across control plane and worker nodes."
    }
  }
}

locals {
  installer_image = coalesce(var.installer_image, "ghcr.io/siderolabs/installer:v${var.talos_version}")

  cp_nodes = { for n in var.control_plane_nodes : n.name => n }

  worker_groups = { for n in var.worker_nodes : n.name => n if n.mac != null }

  first_cp = var.control_plane_nodes[0]

  # Kubernetes version the cluster runs. Defaults to whatever the generated
  # machine config embeds; set var.kubernetes_version to drive upgrades via
  # talos_cluster's upgrade-k8s procedure.
  kubernetes_version = coalesce(
    var.kubernetes_version,
    yamldecode(data.talos_machine_configuration.control_plane[local.first_cp.name].machine_configuration).cluster.kubernetes.version,
  )

  kernel_url = coalesce(
    var.kernel_url,
    var.factory_schematic_id != null ? "https://pxe.factory.talos.dev/image/${var.factory_schematic_id}/v${var.talos_version}/kernel-amd64" : "https://github.com/siderolabs/talos/releases/download/v${var.talos_version}/vmlinuz-amd64",
  )

  initrd_url = coalesce(
    var.initrd_url,
    var.factory_schematic_id != null ? "https://factory.talos.dev/image/${var.factory_schematic_id}/v${var.talos_version}/initramfs-amd64.xz" : "https://github.com/siderolabs/talos/releases/download/v${var.talos_version}/initramfs-amd64.xz",
  )

  common_patch = yamlencode({
    machine = {
      install = {
        disk  = var.install_disk
        image = local.installer_image
        wipe  = true
        extraKernelArgs = [
          "talos.platform=metal",
          "reboot=k",
        ]
      }
    }
  })

  control_plane_patch = yamlencode({
    machine = {
      network = {
        interfaces = [{
          deviceSelector = { physical = true }
          dhcp           = false
          vip            = { ip = var.vip }
          routes = [{
            network = "0.0.0.0/0"
            gateway = var.gateway
          }]
        }]
      }
    }
    cluster = {
      allowSchedulingOnControlPlanes = var.allow_scheduling_on_control_planes
    }
  })

  boot_args_common = [
    "initrd=initramfs.xz",
    "init_on_alloc=1",
    "init_on_free=1",
    "slab_nomerge",
    "pti=on",
    "console=tty0",
    "console=ttyS0",
    "printk.devkmsg=on",
    "talos.platform=metal",
  ]
}

# ---------------------------------------------------------------------------
# Machine configurations (one per control plane node, one shared worker config)
# ---------------------------------------------------------------------------

data "talos_machine_configuration" "control_plane" {
  for_each = local.cp_nodes

  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = var.cluster_endpoint
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  config_patches = [
    local.common_patch,
    local.control_plane_patch,
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = { physical = true }
            addresses      = ["${each.value.ip}${var.cidr_prefix}"]
          }]
        }
      }
    }),
  ]
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = var.cluster_endpoint
  talos_version      = "v${var.talos_version}"
  kubernetes_version = var.kubernetes_version
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  config_patches = [local.common_patch]
}

# ---------------------------------------------------------------------------
# Matchbox assets (machine configs served over HTTP)
# ---------------------------------------------------------------------------

resource "local_file" "asset_control_plane" {
  for_each             = data.talos_machine_configuration.control_plane
  filename             = "${var.build_dir}/assets/${each.key}.yaml"
  sensitive_content    = each.value.machine_configuration
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_file" "asset_worker" {
  filename             = "${var.build_dir}/assets/worker.yaml"
  sensitive_content    = data.talos_machine_configuration.worker.machine_configuration
  file_permission      = "0600"
  directory_permission = "0700"
}

# ---------------------------------------------------------------------------
# Boot assets (kernel + initramfs) served by matchbox
# ---------------------------------------------------------------------------

resource "null_resource" "boot_assets" {
  count = var.download_boot_assets ? 1 : 0

  triggers = {
    kernel_url    = local.kernel_url
    initrd_url    = local.initrd_url
    kernel_sha256 = var.kernel_sha256 == null ? "" : var.kernel_sha256
    initrd_sha256 = var.initrd_sha256 == null ? "" : var.initrd_sha256
  }

  provisioner "local-exec" {
    command = <<-EOT
      bash ${path.module}/../tools/fetch-boot-assets.sh \
        "${abspath(var.build_dir)}/assets" \
        "${local.kernel_url}" \
        "${local.initrd_url}" \
        "${var.kernel_sha256 == null ? "" : var.kernel_sha256}" \
        "${var.initrd_sha256 == null ? "" : var.initrd_sha256}"
    EOT
  }
}

# ---------------------------------------------------------------------------
# Matchbox groups + profiles (matchbox hot-reloads these from disk)
# ---------------------------------------------------------------------------

resource "local_file" "group_control_plane" {
  for_each = local.cp_nodes
  filename = "${var.build_dir}/groups/${each.key}.json"
  content = jsonencode({
    id      = each.key
    name    = each.key
    profile = each.key
    selector = {
      mac = each.value.mac
    }
  })
}

resource "local_file" "profile_control_plane" {
  for_each = local.cp_nodes
  filename = "${var.build_dir}/profiles/${each.key}.json"
  content = jsonencode({
    id   = each.key
    name = each.key
    boot = {
      kernel = "/assets/vmlinuz"
      initrd = ["/assets/initramfs.xz"]
      args = concat(
        local.boot_args_common,
        [
          "ip=${each.value.ip}::${var.gateway}:${var.netmask}::${each.value.interface}:off:::",
          "talos.config=${var.matchbox_http_endpoint}/assets/${each.key}.yaml",
        ]
      )
    }
  })

  depends_on = [
    local_file.asset_control_plane,
    null_resource.boot_assets,
  ]
}

resource "local_file" "group_default" {
  filename = "${var.build_dir}/groups/default.json"
  content = jsonencode({
    id      = "default"
    name    = "default"
    profile = "default"
  })
}

resource "local_file" "profile_default" {
  filename = "${var.build_dir}/profiles/default.json"
  content = jsonencode({
    id   = "default"
    name = "default"
    boot = {
      kernel = "/assets/vmlinuz"
      initrd = ["/assets/initramfs.xz"]
      args = concat(
        local.boot_args_common,
        ["talos.config=${var.matchbox_http_endpoint}/assets/worker.yaml"]
      )
    }
  })

  depends_on = [
    local_file.asset_worker,
    null_resource.boot_assets,
  ]
}

# Optional explicit worker MAC bindings (same worker profile, just a selector)
resource "local_file" "group_worker" {
  for_each = local.worker_groups
  filename = "${var.build_dir}/groups/${each.key}.json"
  content = jsonencode({
    id      = each.key
    name    = each.key
    profile = "default"
    selector = {
      mac = each.value.mac
    }
  })
}

# ---------------------------------------------------------------------------
# Client configuration (talosconfig)
# ---------------------------------------------------------------------------

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n in var.control_plane_nodes : n.ip]
  nodes                = [for n in var.control_plane_nodes : n.ip]
}

resource "local_file" "talosconfig" {
  filename             = "${var.build_dir}/talosconfig"
  sensitive_content    = data.talos_client_configuration.this.talos_config
  file_permission      = "0600"
  directory_permission = "0700"
}

# Embedded iPXE loader script (burn to USB / chain from existing PXE)
resource "local_file" "boot_ipxe" {
  filename = "${var.build_dir}/boot.ipxe"
  content  = <<-EOT
    #!ipxe
    echo Configure dhcp .... &&
    dhcp &&
    chain ${var.matchbox_http_endpoint}/boot.ipxe
  EOT
}

# ---------------------------------------------------------------------------
# etcd bootstrap (gated: run after the first CP node has PXE booted)
# ---------------------------------------------------------------------------

# Fail fast if the talosctl client version does not match var.talos_version.
data "external" "talosctl_version" {
  count = var.bootstrap || var.apply_to_running_nodes ? 1 : 0

  program = ["bash", "${path.module}/../tools/check-talosctl-version.sh", "v${var.talos_version}"]
}

resource "talos_machine_bootstrap" "this" {
  count = var.bootstrap ? 1 : 0

  node                 = local.first_cp.ip
  endpoint             = local.first_cp.ip
  client_configuration = talos_machine_secrets.this.client_configuration

  lifecycle {
    precondition {
      condition     = data.external.talosctl_version[0].result["match"] == "true"
      error_message = "talosctl client version must match var.talos_version (v${var.talos_version})."
    }
  }

  depends_on = [
    local_file.asset_control_plane,
    local_file.profile_control_plane,
  ]
}

# Post-bootstrap health gate: waits for all CP nodes Ready + Talos services healthy.
resource "null_resource" "health_check" {
  count = var.bootstrap ? 1 : 0

  triggers = {
    bootstrap_id = talos_machine_bootstrap.this[0].id
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/../tools/health-check.sh ${abspath(var.build_dir)} ${var.health_check_timeout} ${join(" ", [for n in var.control_plane_nodes : n.ip])}"
  }

  depends_on = [talos_machine_bootstrap.this]
}

# ---------------------------------------------------------------------------
# kubeconfig (re-generated whenever the talosconfig changes, so it never goes stale)
# ---------------------------------------------------------------------------

resource "null_resource" "kubeconfig" {
  count = var.bootstrap ? 1 : 0

  triggers = {
    bootstrap_id     = talos_machine_bootstrap.this[0].id
    talosconfig_hash = filesha256(local_file.talosconfig.filename)
  }

  provisioner "local-exec" {
    command = <<-EOT
      talosctl --talosconfig ${abspath(var.build_dir)}/talosconfig \
        kubeconfig ${abspath(var.build_dir)}/kubeconfig --force-overwrite
    EOT
  }

  depends_on = [null_resource.health_check]
}

# ---------------------------------------------------------------------------
# Kubernetes upgrade workflow (talosctl upgrade-k8s, health-gated)
# Set var.upgrade_kubernetes_version (e.g. "v1.30.4") and run:
#   terraform apply -var bootstrap=true -var upgrade_kubernetes_version=v1.30.4
# Do NOT combine with apply_to_running_nodes in the same run.
# ---------------------------------------------------------------------------

resource "null_resource" "upgrade_k8s" {
  count = var.upgrade_kubernetes_version != null ? 1 : 0

  triggers = {
    target_version = var.upgrade_kubernetes_version
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/../tools/upgrade-k8s.sh ${abspath(var.build_dir)} ${var.upgrade_kubernetes_version} ${join(" ", [for n in var.control_plane_nodes : n.ip])}"
  }

  depends_on = [null_resource.kubeconfig]
}

# ---------------------------------------------------------------------------
# Optional: push generated config to running nodes (drift correction)
# ---------------------------------------------------------------------------

# Discover worker IPs from the cluster (requires kubeconfig from bootstrap).
data "external" "worker_ips" {
  count = var.apply_to_running_nodes ? 1 : 0

  program = ["bash", "${path.module}/../tools/worker-ips.sh", abspath(var.build_dir)]

  depends_on = [null_resource.kubeconfig]
}

resource "talos_machine_configuration_apply" "control_plane" {
  for_each = var.apply_to_running_nodes ? local.cp_nodes : {}

  node                        = each.value.ip
  endpoint                    = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane[each.key].machine_configuration
  apply_mode                  = "staged_if_needing_reboot"
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.apply_to_running_nodes ? data.external.worker_ips[0].result : {}

  node                        = each.value
  endpoint                    = each.value
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  apply_mode                  = "staged_if_needing_reboot"
}
