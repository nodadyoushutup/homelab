resource "proxmox_virtual_environment_download_file" "ubuntu_24_cloud_image" {
  node_name           = "pve"
  datastore_id        = "local"
  content_type        = "iso"
  file_name           = "ubuntu-24.04-ndysu-0.0.2-amd64.img"
  url                 = "https://webserver.image.nodadyoushutup.com/ubuntu-24.04-ndysu-0.0.2-amd64.qcow2"
  verify              = false
  overwrite           = true
  overwrite_unmanaged = true
  upload_timeout      = 1800
}

resource "proxmox_virtual_environment_download_file" "talos_v1_12_4cloud_image" {
  node_name           = "pve"
  datastore_id        = "local"
  content_type        = "iso"
  file_name           = "talos-v1.12.4-nocloud-amd64.iso"
  url                 = "https://factory.talos.dev/image/eda6c02d94377f983da3aa0c8a98c58dc6b2b9341ec42512161eb7661acb526d/v1.12.4/nocloud-amd64.iso"
  verify              = false
  overwrite           = true
  overwrite_unmanaged = true
  upload_timeout      = 1800
}

resource "proxmox_virtual_environment_file" "development_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.development_user_config_path)
    file_name = "development-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_cp_0_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_cp_0_user_config_path)
    file_name = "k8s-cp-0-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_0_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_0_user_config_path)
    file_name = "k8s-wk-0-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_1_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_1_user_config_path)
    file_name = "k8s-wk-1-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_2_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_2_user_config_path)
    file_name = "k8s-wk-2-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_3_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_3_user_config_path)
    file_name = "k8s-wk-3-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_4_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_4_user_config_path)
    file_name = "k8s-wk-4-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_5_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_5_user_config_path)
    file_name = "k8s-wk-5-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_6_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_6_user_config_path)
    file_name = "k8s-wk-6-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_7_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_7_user_config_path)
    file_name = "k8s-wk-7-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_8_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_8_user_config_path)
    file_name = "k8s-wk-8-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_9_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_9_user_config_path)
    file_name = "k8s-wk-9-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_10_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_10_user_config_path)
    file_name = "k8s-wk-10-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "development_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.development_network_config_path)
    file_name = "development-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_cp_0_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_cp_0_network_config_path)
    file_name = "k8s-cp-0-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_0_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_0_network_config_path)
    file_name = "k8s-wk-0-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_1_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_1_network_config_path)
    file_name = "k8s-wk-1-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_2_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_2_network_config_path)
    file_name = "k8s-wk-2-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_3_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_3_network_config_path)
    file_name = "k8s-wk-3-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_4_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_4_network_config_path)
    file_name = "k8s-wk-4-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_5_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_5_network_config_path)
    file_name = "k8s-wk-5-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_6_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_6_network_config_path)
    file_name = "k8s-wk-6-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_7_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_7_network_config_path)
    file_name = "k8s-wk-7-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_8_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_8_network_config_path)
    file_name = "k8s-wk-8-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_9_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_9_network_config_path)
    file_name = "k8s-wk-9-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "k8s_wk_10_network_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file(var.k8s_wk_10_network_config_path)
    file_name = "k8s-wk-10-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "development_vm" {
  node_name = "pve"
  vm_id     = 1101
  name      = "development"
  bios      = "ovmf"
  machine   = "q35"
  started   = true
  on_boot   = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    file_id      = proxmox_virtual_environment_download_file.ubuntu_24_cloud_image.id
    size         = 20
  }

  initialization {
    datastore_id         = "local-lvm"
    user_data_file_id    = proxmox_virtual_environment_file.development_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.development_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:70"
  }

  tags = ["terraform", "ubuntu"]

  depends_on = [
    proxmox_virtual_environment_download_file.ubuntu_24_cloud_image,
    proxmox_virtual_environment_file.development_user_config,
    proxmox_virtual_environment_file.development_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_cp_0_vm" {
  node_name = "pve"
  vm_id     = 2201
  name      = "k8s-cp-0"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_cp_0_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_cp_0_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:71"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_cp_0_user_config,
    proxmox_virtual_environment_file.k8s_cp_0_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_0_vm" {
  node_name = "pve"
  vm_id     = 2202
  name      = "k8s-wk-0"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_0_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_0_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:72"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_0_user_config,
    proxmox_virtual_environment_file.k8s_wk_0_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_1_vm" {
  node_name = "pve"
  vm_id     = 2203
  name      = "k8s-wk-1"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_1_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_1_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:73"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_1_user_config,
    proxmox_virtual_environment_file.k8s_wk_1_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_2_vm" {
  node_name = "pve"
  vm_id     = 2204
  name      = "k8s-wk-2"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_2_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_2_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:74"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_2_user_config,
    proxmox_virtual_environment_file.k8s_wk_2_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_3_vm" {
  node_name = "pve"
  vm_id     = 2205
  name      = "k8s-wk-3"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_3_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_3_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:75"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_3_user_config,
    proxmox_virtual_environment_file.k8s_wk_3_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_4_vm" {
  node_name = "pve"
  vm_id     = 2206
  name      = "k8s-wk-4"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_4_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_4_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:76"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_4_user_config,
    proxmox_virtual_environment_file.k8s_wk_4_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_5_vm" {
  node_name = "pve"
  vm_id     = 2207
  name      = "k8s-wk-5"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_5_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_5_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:77"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_5_user_config,
    proxmox_virtual_environment_file.k8s_wk_5_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_6_vm" {
  node_name = "pve"
  vm_id     = 2208
  name      = "k8s-wk-6"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_6_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_6_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:78"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_6_user_config,
    proxmox_virtual_environment_file.k8s_wk_6_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_7_vm" {
  node_name = "pve"
  vm_id     = 2209
  name      = "k8s-wk-7"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_7_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_7_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:79"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_7_user_config,
    proxmox_virtual_environment_file.k8s_wk_7_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_8_vm" {
  node_name = "pve"
  vm_id     = 2210
  name      = "k8s-wk-8"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_8_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_8_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:7A"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_8_user_config,
    proxmox_virtual_environment_file.k8s_wk_8_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_9_vm" {
  node_name = "pve"
  vm_id     = 2211
  name      = "k8s-wk-9"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_9_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_9_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:7B"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_9_user_config,
    proxmox_virtual_environment_file.k8s_wk_9_network_config,
  ]
}

resource "proxmox_virtual_environment_vm" "k8s_wk_10_vm" {
  node_name = "pve"
  vm_id     = 2212
  name      = "k8s-wk-10"
  bios      = "ovmf"
  machine   = "q35"
  boot_order = [
    "scsi0",
    "ide2",
  ]
  started = true
  on_boot = true

  operating_system {
    type = "l26"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "virtualization"
    interface    = "scsi0"
    size         = 20
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image.id
  }

  initialization {
    datastore_id         = "local-lvm"
    interface            = "ide0"
    user_data_file_id    = proxmox_virtual_environment_file.k8s_wk_10_user_config.id
    network_data_file_id = proxmox_virtual_environment_file.k8s_wk_10_network_config.id
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:F3:49:7C"
  }

  tags = ["terraform", "talos"]

  depends_on = [
    proxmox_virtual_environment_download_file.talos_v1_12_4cloud_image,
    proxmox_virtual_environment_file.k8s_wk_10_user_config,
    proxmox_virtual_environment_file.k8s_wk_10_network_config,
  ]
}
