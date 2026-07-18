packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "image_version" {
  type        = string
  description = "Version string used in output directory and image filename (e.g. 0.0.1)."
}

variable "ubuntu_release" {
  type        = string
  default     = "24.04"
  description = "Ubuntu LTS release to build (e.g. 24.04 or 26.04). Drives the cloud image URL and output naming."

  validation {
    condition     = contains(["24.04", "26.04"], var.ubuntu_release)
    error_message = "The ubuntu_release value must be one of '24.04' or '26.04'."
  }
}

variable "output_root" {
  type        = string
  default     = "output"
  description = "Base directory for build output. Local builds set this to the NFS-backed data/packer directory served by the cloud image repository (so no upload is needed); CI leaves the default."
}

variable "gui" {
  type        = string
  default     = "headless"
  description = "Desktop environment to install (headless|gnome|kde|xfce). headless installs no GUI."

  validation {
    condition     = contains(["headless", "gnome", "kde", "xfce"], var.gui)
    error_message = "The gui value must be one of 'headless', 'gnome', 'kde', or 'xfce'."
  }
}

variable "install_node_exporter" {
  type        = bool
  default     = false
  description = "Install the host-level Prometheus node_exporter systemd service. Default false: swarm/k8s hosts already run node_exporter as a container, so a host install would double-export. Enable only for hosts monitored directly (not in the swarm/cluster)."
}

variable "amd64_accelerator" {
  type        = string
  default     = "kvm"
  description = "QEMU accelerator for amd64 builds (kvm, tcg, or none)."

  validation {
    condition     = contains(["kvm", "tcg", "none"], var.amd64_accelerator)
    error_message = "The amd64_accelerator value must be one of 'kvm', 'tcg', or 'none'."
  }
}

variable "arm64_accelerator" {
  type        = string
  default     = "kvm"
  description = "QEMU accelerator for arm64 builds (kvm, tcg, or none)."

  validation {
    condition     = contains(["kvm", "tcg", "none"], var.arm64_accelerator)
    error_message = "The arm64_accelerator value must be one of 'kvm', 'tcg', or 'none'."
  }
}

locals {
  # Packer omits -cpu by default; QEMU's default guest CPU is not KVM-valid on some
  # AArch64 hosts (e.g. Pi): "KVM is not supported for this guest CPU type". Use host
  # under KVM; use a generic model for TCG.
  arm64_qemu_cpu_model = var.arm64_accelerator == "kvm" ? "host" : "cortex-a57"

  # Canonical release cloud images keyed by numeric version (no codename needed):
  # https://cloud-images.ubuntu.com/releases/<release>/release/ubuntu-<release>-server-cloudimg-<arch>.img
  cloud_image_base    = "https://cloud-images.ubuntu.com/releases/${var.ubuntu_release}/release"
  cloud_image_amd64   = "${local.cloud_image_base}/ubuntu-${var.ubuntu_release}-server-cloudimg-amd64.img"
  cloud_image_arm64   = "${local.cloud_image_base}/ubuntu-${var.ubuntu_release}-server-cloudimg-arm64.img"
  cloud_image_sha_url = "file:${local.cloud_image_base}/SHA256SUMS"

  image_prefix = "ubuntu-${var.ubuntu_release}-ndysu"
}

source "qemu" "ubuntu_amd64" {
  accelerator  = var.amd64_accelerator
  communicator = "ssh"
  cpus         = 2
  memory       = 2048
  headless     = true

  iso_url          = local.cloud_image_amd64
  iso_checksum     = local.cloud_image_sha_url
  disk_image       = true
  disk_size        = "12288M"
  use_backing_file = false
  format           = "qcow2"
  disk_interface   = "virtio"

  cd_label = "cidata"
  cd_files = [
    "cloud-init/meta-data",
    "cloud-init/user-data",
  ]

  ssh_username         = "packer"
  ssh_private_key_file = "keys/packer-nodadyoushutup"
  ssh_timeout          = "20m"

  output_directory = "${var.output_root}/${local.image_prefix}/${var.image_version}/amd64"
  vm_name          = "${local.image_prefix}-${var.image_version}-amd64.qcow2"

  shutdown_command = "sudo -E shutdown -P now"
}

source "qemu" "ubuntu_arm64" {
  accelerator = var.arm64_accelerator
  qemu_binary = "qemu-system-aarch64"

  communicator = "ssh"
  cpus         = 2
  cpu_model    = local.arm64_qemu_cpu_model
  memory       = 2048
  headless     = true
  machine_type = "virt"

  iso_url          = local.cloud_image_arm64
  iso_checksum     = local.cloud_image_sha_url
  disk_image       = true
  disk_size        = "12288M"
  use_backing_file = false
  format           = "qcow2"
  disk_interface   = "virtio"

  # Ubuntu arm64 cloud images boot via UEFI on `virt`. Without AAVMF pflash, QEMU
  # starts but the guest never reaches sshd; PACKER_LOG then shows TCP to the
  # hostfwd port followed by "Timeout during SSH handshake" (no SSH banner).
  # Paths are from the `qemu-efi-aarch64` package (installed by scripts/install/packer.sh).
  efi_firmware_code = "/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd"
  efi_firmware_vars = "/usr/share/AAVMF/AAVMF_VARS.fd"

  cd_label = "cidata"
  cd_files = [
    "cloud-init/meta-data",
    "cloud-init/user-data",
  ]

  ssh_username         = "packer"
  ssh_private_key_file = "keys/packer-nodadyoushutup"
  ssh_timeout          = "30m"

  output_directory = "${var.output_root}/${local.image_prefix}/${var.image_version}/arm64"
  vm_name          = "${local.image_prefix}-${var.image_version}-arm64.qcow2"

  shutdown_command = "sudo -E shutdown -P now"
}

build {
  name = "ubuntu-ndysu"
  sources = [
    "source.qemu.ubuntu_amd64",
    "source.qemu.ubuntu_arm64",
  ]

  provisioner "file" {
    source      = "../scripts/install"
    destination = "/tmp"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "find /tmp/install -maxdepth 1 -type f -name '*.sh' -exec chmod 0755 {} +",
      "AUTOMATION_TARGET_USER=nodadyoushutup AUTOMATION_DOCKER_VERIFY=0 /tmp/install/automation_tooling.sh",
      "if [ '${var.install_node_exporter}' = 'true' ]; then /tmp/install/node_exporter.sh; else echo '[INFO] host node_exporter install skipped (install_node_exporter=false; swarm/k8s container exporter handles metrics).'; fi",
      "if [ '${var.gui}' != 'headless' ]; then /tmp/install/${var.gui}.sh; else echo '[INFO] GUI install skipped (headless).'; fi",
    ]
  }

  provisioner "file" {
    source      = "scripts/cleanup-image.sh"
    destination = "/tmp/cleanup-image.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/cleanup-image.sh",
      "/tmp/cleanup-image.sh",
    ]
  }
}
