variable "mount_path" {
  description = "Path where KV v2 will be mounted"
  type        = string
  default     = "secret"
}

variable "secrets" {
  description = "Grouped secret payloads keyed by group and secret name"
  type        = map(map(map(string)))
  default     = {}

  validation {
    condition = alltrue([
      for group_name, _ in var.secrets : can(regex("^[a-z0-9_-]+$", group_name))
    ])
    error_message = "Each secrets group key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }

  validation {
    condition = alltrue(flatten([
      for _, grouped_entries in var.secrets : [
        for secret_name, _ in grouped_entries : can(regex("^[a-z0-9_-]+$", secret_name))
      ]
    ]))
    error_message = "Each secret name key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }
}

variable "secret_files" {
  description = "Grouped secret field file-path refs keyed by group and secret name"
  type        = map(map(map(string)))
  default     = {}

  validation {
    condition = alltrue([
      for group_name, _ in var.secret_files : can(regex("^[a-z0-9_-]+$", group_name))
    ])
    error_message = "Each secret_files group key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }

  validation {
    condition = alltrue(flatten([
      for _, grouped_entries in var.secret_files : [
        for secret_name, _ in grouped_entries : can(regex("^[a-z0-9_-]+$", secret_name))
      ]
    ]))
    error_message = "Each secret_files name key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }
}

variable "dns_nameservers" {
  description = <<-EOT
    DNS nameservers for Swarm task dns_config (and standalone runner dns). Set only in
    CONFIG_DIR/terraform/providers/dns.tfvars (merged by swarm_pipeline.sh before stack tfvars).
  EOT
  type        = list(string)
  sensitive   = true
}

variable "swarm_nfs_server" {
  description = <<-EOT
    Optional legacy; NFS mount options are swarm_nfs_volume_o_rw / swarm_nfs_volume_o_ro in nfs.tfvars.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "swarm_nfs_code_device" {
  description = <<-EOT
    NFS device/export for repo code (e.g. ":/mnt/eapp/code"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_config_device" {
  description = <<-EOT
    NFS device/export for shared config (e.g. ":/mnt/eapp/code/homelab/.config"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_type" {
  description = <<-EOT
    Docker local volume driver_opts.type for NFS-backed mounts (typically "nfs"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_o_rw" {
  description = <<-EOT
    Docker local volume driver_opts.o for read-write NFS (comma-separated options, e.g. addr=HOST,nfsvers=4.2,rw). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_o_ro" {
  description = <<-EOT
    Docker local volume driver_opts.o for read-only NFS (e.g. addr=HOST,nfsvers=4.2,ro). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}
