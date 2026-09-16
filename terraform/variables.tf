variable "cluster_name" {
  description = "Name of the Talos cluster."
  type        = string
  default     = "test-cluster"
}

variable "talos_version" {
  description = "Talos version to deploy (talosctl must match this exactly)."
  type        = string
  default     = "1.7.6"
}

variable "kubernetes_version" {
  description = "Kubernetes version baked into the generated machine configuration. Defaults to the Talos provider default when null."
  type        = string
  default     = null
}

variable "cluster_endpoint" {
  description = "API server endpoint, e.g. https://10.10.2.150:6443 (VIP or first control plane node)."
  type        = string
}

variable "vip" {
  description = "Virtual IP used by the control plane nodes (talos-vip)."
  type        = string
}

variable "gateway" {
  description = "IPv4 default gateway pushed to control plane nodes."
  type        = string
  default     = "10.10.1.1"
}

variable "netmask" {
  description = "Netmask used in the iPXE ip= kernel argument (dotted form)."
  type        = string
  default     = "255.255.0.0"
}

variable "cidr_prefix" {
  description = "CIDR prefix used for the static addresses in the Talos machine config, e.g. /16."
  type        = string
  default     = "/16"
}

variable "matchbox_http_endpoint" {
  description = "Base URL of the matchbox HTTP server that serves boot assets."
  type        = string
  default     = "http://10.10.1.47:8080"
}

variable "install_disk" {
  description = "Disk Talos installs onto."
  type        = string
  default     = "/dev/nvme0n1"
}

variable "installer_image" {
  description = "Talos installer image. Defaults to ghcr.io/siderolabs/installer:v<talos_version> when null."
  type        = string
  default     = null
}

variable "factory_schematic_id" {
  description = "Optional Talos image factory schematic id (for hardware patches such as amdgpu-firmware). When set, kernel/initrd are downloaded from the factory instead of upstream GitHub releases."
  type        = string
  default     = null
}

variable "kernel_url" {
  description = "Explicit kernel URL. Overrides factory/GitHub defaults when set."
  type        = string
  default     = null
}

variable "initrd_url" {
  description = "Explicit initramfs URL. Overrides factory/GitHub defaults when set."
  type        = string
  default     = null
}

variable "kernel_sha256" {
  description = "Optional SHA256 of the kernel image. When set, the downloaded vmlinuz is verified before use."
  type        = string
  default     = null
}

variable "initrd_sha256" {
  description = "Optional SHA256 of the initramfs image. When set, the downloaded initramfs.xz is verified before use."
  type        = string
  default     = null
}

variable "allow_scheduling_on_control_planes" {
  description = "Allow workload scheduling on control plane nodes."
  type        = bool
  default     = true
}

variable "control_plane_nodes" {
  description = "Control plane nodes. Each needs a MAC (matchbox selector) and a static IP outside the DHCP range."
  type = list(object({
    name      = string
    mac       = string
    ip        = string
    interface = optional(string, "eno1")
  }))
}

variable "worker_nodes" {
  description = "Optional explicit worker bindings. Workers without a MAC are covered by the default matchbox group and use DHCP."
  type = list(object({
    name = string
    mac  = optional(string)
  }))
  default = []
}

variable "bootstrap" {
  description = "Bootstrap etcd on the first control plane node. Set to true only after the first control plane node has PXE booted and is reachable."
  type        = bool
  default     = false
}

variable "health_check_timeout" {
  description = "How long to wait for the cluster to become healthy after bootstrap (seconds)."
  type        = string
  default     = "600"
}

variable "upgrade_kubernetes_version" {
  description = "Target Kubernetes version for talosctl upgrade-k8s (e.g. v1.30.4). Null = no upgrade. Requires bootstrap=true and must not be combined with apply_to_running_nodes."
  type        = string
  default     = null
}

variable "apply_to_running_nodes" {
  description = "Apply the generated machine configuration to already-running nodes (config drift correction). Requires every listed node to be reachable."
  type        = bool
  default     = false
}

variable "download_boot_assets" {
  description = "Download vmlinuz/initramfs into the build assets directory via curl."
  type        = bool
  default     = true
}

variable "build_dir" {
  description = "Directory (relative to this module) where matchbox assets, groups, profiles, talosconfig and boot.ipxe are generated. Point your matchbox server at this directory."
  type        = string
  default     = "build"
}

variable "manage_matchbox" {
  description = "Run the matchbox server as a Terraform-managed Docker container (network_mode=host) mounting the build dir."
  type        = bool
  default     = false
}

variable "matchbox_version" {
  description = "Matchbox container image tag."
  type        = string
  default     = "v0.10.0"
}

variable "matchbox_http_port" {
  description = "Port the matchbox HTTP server listens on."
  type        = number
  default     = 8080
}

variable "docker_host" {
  description = "Docker daemon address (e.g. unix:///var/run/docker.sock). Null uses DOCKER_HOST env / default socket."
  type        = string
  default     = null
}

variable "build_ipxe_usb" {
  description = "Build the iPXE boot USB image (ipxe.usb) with the generated boot.ipxe embedded, via tools/ipxe/build-ipxe-usb.sh (requires Docker)."
  type        = bool
  default     = false
}
