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

variable "arch_snapshot" {
  type        = string
  default     = "20260715.556894"
  description = "Arch Linux cloud image snapshot (dated build id under images/v<snapshot>/). Update alongside arch_image_checksum."
}

variable "arch_image_checksum" {
  type        = string
  default     = "sha256:f419d4e29aebfc017ad4c9de330a3be0d7eefba710b269108b116aaca1122926"
  description = "SHA256 of the pinned Arch cloudimg qcow2. Update whenever arch_snapshot changes."
}

variable "output_root" {
  type        = string
  default     = "output"
  description = "Base directory for build output. Local builds set this to the NFS-backed data/packer directory served by the cloud image repository."
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

variable "amd64_accelerator" {
  type        = string
  default     = "kvm"
  description = "QEMU accelerator for amd64 builds (kvm, tcg, or none)."

  validation {
    condition     = contains(["kvm", "tcg", "none"], var.amd64_accelerator)
    error_message = "The amd64_accelerator value must be one of 'kvm', 'tcg', or 'none'."
  }
}

locals {
  # Arch upstream publishes an amd64 (x86_64) cloud image only; there is no
  # official arm64 image, so this template has a single amd64 source.
  cloud_image_amd64 = "https://geo.mirror.pkgbuild.com/images/v${var.arch_snapshot}/Arch-Linux-x86_64-cloudimg-${var.arch_snapshot}.qcow2"

  image_prefix = "arch-ndysu"
}

source "qemu" "arch_amd64" {
  accelerator  = var.amd64_accelerator
  communicator = "ssh"
  cpus         = 2
  memory       = 2048
  headless     = true

  iso_url          = local.cloud_image_amd64
  iso_checksum     = var.arch_image_checksum
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

build {
  name = "arch-ndysu"
  sources = [
    "source.qemu.arch_amd64",
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
      "/tmp/install/node_exporter.sh",
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
