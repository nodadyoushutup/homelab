# main.tf
# Proxmox cloud images, cloud-init snippets, and VMs, driven by the
# proxmox_images / proxmox_machines tfvars (managed by homelab-config).

resource "proxmox_virtual_environment_download_file" "image" {
  for_each = local.proxmox_images

  node_name           = try(each.value.node_name, "pve")
  datastore_id        = try(each.value.datastore_id, "local")
  content_type        = try(each.value.content_type, "iso")
  file_name           = each.value.file_name
  url                 = each.value.url
  verify              = try(each.value.verify, false)
  overwrite           = try(each.value.overwrite, true)
  overwrite_unmanaged = try(each.value.overwrite_unmanaged, true)
  upload_timeout      = try(each.value.upload_timeout, 1800)
}

resource "proxmox_virtual_environment_file" "user_config" {
  for_each = local.proxmox_machines

  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.node_name

  source_raw {
    data      = file(each.value.user_config_path)
    file_name = "${each.key}-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "network_config" {
  for_each = local.proxmox_machines

  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.node_name

  source_raw {
    data      = file(each.value.network_config_path)
    file_name = "${each.key}-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.proxmox_machines

  node_name  = each.value.node_name
  vm_id      = each.value.vm_id
  name       = each.key
  bios       = each.value.bios
  machine    = each.value.machine
  boot_order = each.value.boot_order
  started    = each.value.started
  on_boot    = each.value.on_boot

  operating_system {
    type = each.value.os_type
  }

  efi_disk {
    datastore_id      = each.value.efi_datastore_id
    type              = each.value.efi_type
    pre_enrolled_keys = each.value.efi_pre_enrolled
  }

  cpu {
    cores = each.value.cores
    type  = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = each.value.disk_datastore_id
    interface    = each.value.disk_interface
    file_id      = each.value.disk_image == null ? null : proxmox_virtual_environment_download_file.image[each.value.disk_image].id
    size         = each.value.disk_size
  }

  dynamic "cdrom" {
    for_each = each.value.cdrom_image == null ? [] : [each.value.cdrom_image]
    content {
      interface = each.value.cdrom_interface
      file_id   = proxmox_virtual_environment_download_file.image[cdrom.value].id
    }
  }

  initialization {
    datastore_id         = each.value.init_datastore_id
    interface            = each.value.init_interface
    user_data_file_id    = proxmox_virtual_environment_file.user_config[each.key].id
    network_data_file_id = proxmox_virtual_environment_file.network_config[each.key].id
  }

  network_device {
    bridge      = each.value.net_bridge
    model       = each.value.net_model
    mac_address = each.value.net_mac_address
  }

  tags = each.value.tags
}
