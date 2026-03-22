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

variable "kde_profile" {
  type        = string
  default     = null
  description = "Optional KDE profile (desktop|minimal|full). Null disables KDE install."
}

variable "amd64_accelerator" {
  type        = string
  default     = "kvm"
  description = "QEMU accelerator for amd64 builds (kvm or tcg)."

  validation {
    condition     = contains(["kvm", "tcg"], var.amd64_accelerator)
    error_message = "amd64_accelerator must be either 'kvm' or 'tcg'."
  }
}

locals {
  kde_profile_effective = var.kde_profile != null ? var.kde_profile : ""
}

source "qemu" "ubuntu_24_04_amd64" {
  accelerator  = var.amd64_accelerator
  communicator = "ssh"
  cpus         = 2
  memory       = 2048
  headless     = true

  iso_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  iso_checksum     = "file:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"
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

  output_directory = "output/ubuntu-24.04-ndysu/${var.image_version}/amd64"
  vm_name          = "ubuntu-24.04-ndysu-${var.image_version}-amd64.qcow2"

  shutdown_command = "sudo -E shutdown -P now"
}

source "qemu" "ubuntu_24_04_arm64" {
  accelerator = "tcg"
  qemu_binary = "qemu-system-aarch64"

  communicator = "ssh"
  cpus         = 2
  memory       = 2048
  headless     = true
  machine_type = "virt"

  iso_url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
  iso_checksum     = "file:https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"
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
  ssh_timeout          = "30m"

  output_directory = "output/ubuntu-24.04-ndysu/${var.image_version}/arm64"
  vm_name          = "ubuntu-24.04-ndysu-${var.image_version}-arm64.qcow2"

  shutdown_command = "sudo -E shutdown -P now"
}

build {
  name = "ubuntu-24.04-ndysu"
  sources = [
    "source.qemu.ubuntu_24_04_amd64",
    # "source.qemu.ubuntu_24_04_arm64",
  ]

  provisioner "file" {
    source      = "../scripts/install/packages.sh"
    destination = "/tmp/install-packages.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-packages.sh",
      "/tmp/install-packages.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/docker.sh"
    destination = "/tmp/install-docker.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-docker.sh",
      "TARGET_USER=nodadyoushutup DOCKER_VERIFY=0 /tmp/install-docker.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/terraform.sh"
    destination = "/tmp/install-terraform.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-terraform.sh",
      "/tmp/install-terraform.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/ansible.sh"
    destination = "/tmp/install-ansible.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-ansible.sh",
      "/tmp/install-ansible.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/kubectl.sh"
    destination = "/tmp/install-kubectl.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-kubectl.sh",
      "/tmp/install-kubectl.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/k9s.sh"
    destination = "/tmp/install-k9s.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-k9s.sh",
      "/tmp/install-k9s.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/packer.sh"
    destination = "/tmp/install-packer.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-packer.sh",
      "TARGET_USER=nodadyoushutup /tmp/install-packer.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/node_exporter.sh"
    destination = "/tmp/install-node-exporter.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-node-exporter.sh",
      "/tmp/install-node-exporter.sh",
    ]
  }

  provisioner "file" {
    source      = "../scripts/install/kde.sh"
    destination = "/tmp/install-kde.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/install-kde.sh",
      "if [ -n '${local.kde_profile_effective}' ]; then KDE_PROFILE='${local.kde_profile_effective}' /tmp/install-kde.sh; else echo '[INFO] KDE install skipped (kde_profile unset).'; fi",
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
