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

variable "kali_release" {
  type        = string
  default     = "2026.2"
  description = "Kali Linux rolling release checkpoint (e.g. 2026.2). Drives output naming only; the base image is resolved and pinned by scripts/prepare-kali-image.sh."
}

# Kali publishes its cloud image as a .tar.xz containing a single raw disk, not a
# ready-to-boot qcow2. scripts/prepare-kali-image.sh downloads the pinned tarball,
# verifies its upstream SHA256, extracts the raw disk, and converts it to a local
# qcow2. That local qcow2 path (and its checksum) are injected here as vars. The
# packer/upload wrappers always set these before building; the placeholder default
# only exists so `packer validate` passes for the non-selected architecture.
variable "kali_local_image_amd64" {
  type        = string
  default     = "UNSET-run-scripts/prepare-kali-image.sh"
  description = "Local path to the prepared Kali x86_64 qcow2 (set by packer.sh via scripts/prepare-kali-image.sh)."
}

variable "kali_local_image_arm64" {
  type        = string
  default     = "UNSET-run-scripts/prepare-kali-image.sh"
  description = "Local path to the prepared Kali aarch64 qcow2 (set by packer.sh via scripts/prepare-kali-image.sh)."
}

variable "kali_amd64_image_checksum" {
  type        = string
  default     = "none"
  description = "Checksum of the prepared Kali x86_64 qcow2 (sha256:<hex>). Set by packer.sh; the upstream tarball is already verified during preparation."
}

variable "kali_arm64_image_checksum" {
  type        = string
  default     = "none"
  description = "Checksum of the prepared Kali aarch64 qcow2 (sha256:<hex>). Set by packer.sh; the upstream tarball is already verified during preparation."
}

variable "output_root" {
  type        = string
  default     = "output"
  description = "Base directory for build output. Local builds set this to the NFS-backed data/packer directory served by the cloud image repository."
}

# Accepted for parity with the shared packer.sh / pipeline wrappers (which always
# pass -var gui=...), but Kali is kept raw and installs no desktop, so this is a
# no-op here.
variable "gui" {
  type        = string
  default     = "headless"
  description = "Ignored for Kali (raw image, no desktop installed). Present only so the shared build wrappers can pass -var gui=... uniformly."

  validation {
    condition     = contains(["headless", "gnome", "kde", "xfce"], var.gui)
    error_message = "The gui value must be one of 'headless', 'gnome', 'kde', or 'xfce'."
  }
}

variable "install_node_exporter" {
  type        = bool
  default     = false
  description = "Install the host-level Prometheus node_exporter systemd service. Default false. This is the only optional add-on for the otherwise-raw Kali image."
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
  # See ubuntu-ndysu.pkr.hcl: KVM-valid guest CPU is host under KVM, generic for TCG.
  arm64_qemu_cpu_model = var.arm64_accelerator == "kvm" ? "host" : "cortex-a57"

  image_prefix = "kali-${var.kali_release}-ndysu"
}

source "qemu" "kali_amd64" {
  accelerator  = var.amd64_accelerator
  communicator = "ssh"
  cpus         = 2
  memory       = 2048
  headless     = true

  iso_url      = var.kali_local_image_amd64
  iso_checksum = var.kali_amd64_image_checksum
  disk_image   = true
  # Kali's cloud disk is a 25 GiB image; disk_size must be >= that (qemu-img cannot
  # shrink without --shrink), so grow slightly for provisioning headroom.
  disk_size        = "26624M"
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

source "qemu" "kali_arm64" {
  accelerator = var.arm64_accelerator
  qemu_binary = "qemu-system-aarch64"

  communicator = "ssh"
  cpus         = 2
  cpu_model    = local.arm64_qemu_cpu_model
  memory       = 2048
  headless     = true
  machine_type = "virt"

  iso_url          = var.kali_local_image_arm64
  iso_checksum     = var.kali_arm64_image_checksum
  disk_image       = true
  disk_size        = "26624M"
  use_backing_file = false
  format           = "qcow2"
  disk_interface   = "virtio"

  # aarch64 cloud images boot via UEFI on the `virt` machine. AAVMF pflash is
  # required or the guest never reaches sshd (see ubuntu-ndysu.pkr.hcl). Paths
  # come from the qemu-efi-aarch64 firmware package installed by
  # scripts/install/packer.sh.
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
  name = "kali-ndysu"
  sources = [
    "source.qemu.kali_amd64",
    "source.qemu.kali_arm64",
  ]

  # Kali is intentionally kept as a near-raw upstream cloud image: we do NOT run
  # the shared automation toolchain (automation_tooling.sh) or install a desktop.
  # The only optional add-on is the host node_exporter systemd service, and the
  # cleanup pass that strips the ephemeral packer user/keys.
  provisioner "file" {
    source      = "../scripts/install"
    destination = "/tmp"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash -eux '{{ .Path }}'"
    inline = [
      "find /tmp/install -maxdepth 1 -type f -name '*.sh' -exec chmod 0755 {} +",
      "if [ '${var.install_node_exporter}' = 'true' ]; then /tmp/install/node_exporter.sh; else echo '[INFO] host node_exporter install skipped (install_node_exporter=false).'; fi",
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
