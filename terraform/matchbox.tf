# ---------------------------------------------------------------------------
# Matchbox server lifecycle managed by Terraform.
# Requires a reachable Docker daemon (enable Docker Desktop WSL integration or
# set DOCKER_HOST / var.docker_host).
# ---------------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

resource "docker_image" "matchbox" {
  count = var.manage_matchbox ? 1 : 0

  name = "quay.io/poseidon/matchbox:${var.matchbox_version}"
}

resource "docker_container" "matchbox" {
  count = var.manage_matchbox ? 1 : 0

  name         = "${var.cluster_name}${terraform.workspace == "default" ? "" : "-${terraform.workspace}"}-matchbox"
  image        = docker_image.matchbox[0].image_id
  network_mode = "host"
  restart      = "unless-stopped"

  volumes {
    host_path      = abspath(var.build_dir)
    container_path = "/var/lib/matchbox"
  }

  command = [
    "-address=0.0.0.0:${var.matchbox_http_port}",
    "-log-level=debug",
  ]

  depends_on = [
    local_file.asset_control_plane,
    local_file.asset_worker,
    null_resource.boot_assets,
  ]
}

# ---------------------------------------------------------------------------
# Optional: build the iPXE boot USB (embeds the generated boot.ipxe loader).
# Runs tools/ipxe/build-ipxe-usb.sh which uses `docker build --output`.
# ---------------------------------------------------------------------------

resource "null_resource" "ipxe_usb" {
  count = var.build_ipxe_usb ? 1 : 0

  triggers = {
    boot_ipxe_hash = filesha256(local_file.boot_ipxe.filename)
  }

  provisioner "local-exec" {
    command = "../tools/ipxe/build-ipxe-usb.sh"
  }

  depends_on = [local_file.boot_ipxe]
}
