# variables.tf
# External input contract for the Proxmox VM/cloud-init app slice.

variable "proxmox" {
  description = "Proxmox provider login credentials (config-id terraform/providers/proxmox, managed by homelab-config)."
  type        = any
}

variable "proxmox_images" {
  description = "Cloud images / ISOs to download onto Proxmox, keyed by image key (config-id terraform/components/cluster/proxmox/app, managed by homelab-config)."
  type        = any
  default     = {}
}

variable "proxmox_machines" {
  description = "Proxmox VMs and their cloud-init snippets, keyed by machine name (config-id terraform/components/cluster/proxmox/app, managed by homelab-config)."
  type        = any
  default     = {}
}
