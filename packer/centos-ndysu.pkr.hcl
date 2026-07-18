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

variable "centos_stream" {
  type        = string
  default     = "10"
  description = "CentOS Stream major release to build (e.g. 10). Drives the cloud image URL and output naming."
}

variable "centos_snapshot" {
  type        = string
  default     = "20260630.0"
  description = "CentOS Stream GenericCloud snapshot (dated build id). Update alongside the *_image_checksum values."
}

variable "centos_amd64_image_checksum" {
  type        = string
  default     = "sha256:470c034e3165ab7200c48da28cea50c5c82e7392901bf3076b6140f39780a3e1"
  description = "SHA256 of the pinned CentOS Stream x86_64 GenericCloud qcow2. Update whenever centos_snapshot changes."
}

variable "centos_arm64_image_checksum" {
  type        = string
  default     = "sha256:13ec4ffa7de54246c80935a61fe2c3debf14c84685aea2652877df2b5de1b3bf"
  description = "SHA256 of the pinned CentOS Stream aarch64 GenericCloud qcow2. Update whenever centos_snapshot changes."
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
  # CentOS Stream 10 (like RHEL 10) requires an x86-64-v3 CPU baseline. QEMU's
  # default qemu64 CPU only advertises x86-64-v1, so glibc aborts init with
  # "CPU does not support x86-64-v2" and the guest panics before sshd starts.
  # Pass through the host CPU under KVM; use `max` (all emulated features) for TCG.
  amd64_qemu_cpu_model = var.amd64_accelerator == "kvm" ? "host" : "max"

  # See ubuntu-ndysu.pkr.hcl: KVM-valid guest CPU is host under KVM, generic for TCG.
  arm64_qemu_cpu_model = var.arm64_accelerator == "kvm" ? "host" : "cortex-a57"

  cloud_image_base  = "https://cloud.centos.org/centos/${var.centos_stream}-stream"
  cloud_image_amd64 = "${local.cloud_image_base}/x86_64/images/CentOS-Stream-GenericCloud-${var.centos_stream}-${var.centos_snapshot}.x86_64.qcow2"
  cloud_image_arm64 = "${local.cloud_image_base}/aarch64/images/CentOS-Stream-GenericCloud-${var.centos_stream}-${var.centos_snapshot}.aarch64.qcow2"

  image_prefix = "centos-${var.centos_stream}-ndysu"
}

source "qemu" "centos_amd64" {
  accelerator  = var.amd64_accelerator
  communicator = "ssh"
  cpus         = 2
  cpu_model    = local.amd64_qemu_cpu_model
  memory       = 2048
  headless     = true

  iso_url          = local.cloud_image_amd64
  iso_checksum     = var.centos_amd64_image_checksum
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

  # DEBUG: capture the guest serial console so we can see the boot/cloud-init
  # sequence (written to the NFS output_root so it is readable off-agent).
  qemuargs = [
    ["-serial", "file:${var.output_root}/centos-serial-debug-amd64.log"],
  ]

  shutdown_command = "sudo -E shutdown -P now"
}

source "qemu" "centos_arm64" {
  accelerator = var.arm64_accelerator
  qemu_binary = "qemu-system-aarch64"

  communicator = "ssh"
  cpus         = 2
  cpu_model    = local.arm64_qemu_cpu_model
  memory       = 2048
  headless     = true
  machine_type = "virt"

  iso_url          = local.cloud_image_arm64
  iso_checksum     = var.centos_arm64_image_checksum
  disk_image       = true
  disk_size        = "12288M"
  use_backing_file = false
  format           = "qcow2"
  disk_interface   = "virtio"

  # aarch64 cloud images boot via UEFI on the `virt` machine. AAVMF pflash is
  # required or the guest never reaches sshd (see ubuntu-ndysu.pkr.hcl). Paths
  # come from the qemu-efi-aarch64 (Debian/Ubuntu) / edk2-aarch64 (Arch/CentOS)
  # firmware packages installed by scripts/install/packer.sh.
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
  name = "centos-ndysu"
  sources = [
    "source.qemu.centos_amd64",
    "source.qemu.centos_arm64",
  ]

  provisioner "file" {
    source      = "../scripts/install"
    destination = "/tmp"
  }

  provisioner "shell" {
    # CentOS/RHEL sudo does not put /usr/local/bin on PATH for non-login shells,
    # so release-based installers (kubectl/k9s/mc/packer) fail their `command -v`
    # verify even though the binary is in /usr/local/bin. Force a full PATH.
    execute_command = "sudo -E env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -eux '{{ .Path }}'"
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
    execute_command = "sudo -E env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -eux '{{ .Path }}'"
    inline = [
      "chmod +x /tmp/cleanup-image.sh",
      "/tmp/cleanup-image.sh",
    ]
  }
}
