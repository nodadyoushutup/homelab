# locals.tf
# Single source of truth for Proxmox VM/cloud-init values (resources read local.* only).
# Each machine is normalized with defaults for the constant fields so the tfvars
# (managed by homelab-config) stay concise while the resources reproduce the
# previously hardcoded images/VMs exactly.

locals {
  provider_config = { proxmox = var.proxmox }

  proxmox_images = var.proxmox_images

  proxmox_machines = {
    for name, m in var.proxmox_machines : name => {
      vm_id      = m.vm_id
      node_name  = try(m.node_name, "pve")
      bios       = try(m.bios, "ovmf")
      machine    = try(m.machine, "q35")
      started    = try(m.started, true)
      on_boot    = try(m.on_boot, true)
      os_type    = try(m.os_type, "l26")
      cores      = try(m.cores, 2)
      cpu_type   = try(m.cpu_type, "host")
      memory     = m.memory
      tags       = try(m.tags, ["terraform"])
      boot_order = try(m.boot_order, null)

      efi_datastore_id = try(m.efi.datastore_id, "local-lvm")
      efi_type         = try(m.efi.type, "4m")
      efi_pre_enrolled = try(m.efi.pre_enrolled_keys, false)

      disk_datastore_id = try(m.disk.datastore_id, "virtualization")
      disk_interface    = try(m.disk.interface, "scsi0")
      disk_size         = m.disk.size
      disk_image        = try(m.disk.image, null)

      cdrom_interface = try(m.cdrom.interface, null)
      cdrom_image     = try(m.cdrom.image, null)

      init_datastore_id   = try(m.initialization.datastore_id, "local-lvm")
      init_interface      = try(m.initialization.interface, "ide2")
      user_config_path    = m.initialization.user_config_path
      network_config_path = m.initialization.network_config_path

      net_bridge      = try(m.network.bridge, "vmbr0")
      net_model       = try(m.network.model, "virtio")
      net_mac_address = m.network.mac_address
    }
  }
}
