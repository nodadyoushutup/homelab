variable "provider_config" {
  description = "Auth/config payload for the Harbor provider."
  type = object({
    harbor = object({
      url          = string
      username     = string
      password     = optional(string)
      bearer_token = optional(string)
      session_id   = optional(string)
      insecure     = optional(bool)
      api_version  = optional(number)
      robot_prefix = optional(string)
    })
  })
}

variable "manage_system_config" {
  description = "When true, apply the harbor_config_system resource using system_config values."
  type        = bool
  default     = false
}

variable "system_config" {
  description = "Optional system-wide Harbor configuration map (used only when manage_system_config is true)."
  type        = any
  default     = {}
}

variable "projects" {
  description = <<-EOT
    Extra Harbor projects to create/manage, or overrides for the always-declared
    core `homelab` project (same `name` merges on top of module defaults).
  EOT
  type = list(object({
    name                        = string
    public                      = optional(bool)
    vulnerability_scanning      = optional(bool)
    auto_sbom_generation        = optional(bool)
    enable_content_trust        = optional(bool)
    enable_content_trust_cosign = optional(bool)
    deployment_security         = optional(string)
    cve_allowlist               = optional(list(string))
    proxy_speed_kb              = optional(number)
    storage_quota               = optional(number)
    force_destroy               = optional(bool)
  }))
  default = []
}

variable "users" {
  description = "Optional local Harbor users to create/manage."
  type = list(object({
    username  = string
    email     = string
    full_name = string
    password  = string
    admin     = optional(bool)
    comment   = optional(string)
  }))
  default = []
}

variable "project_members" {
  description = "Optional user memberships for managed projects. project_name must reference an entry in projects."
  type = list(object({
    project_name = string
    user_name    = string
    role         = string
  }))
  default = []
}

variable "robot_accounts" {
  description = "Optional robot account specs. Each item should match provider schema for harbor_robot_account."
  type        = list(any)
  default     = []
}

variable "delete_default_library" {
  description = <<-EOT
    When true (default), idempotently delete Harbor's seeded `library` project via the
    REST API on every apply. The project is created by Harbor core during initial DB
    bootstrap and cannot be declaratively managed by the harbor provider without an
    import dance. This null_resource-based cleanup also self-heals if the DB is ever
    re-bootstrapped. Deletion fails if the project still contains repositories (HTTP 412).
  EOT
  type        = bool
  default     = true
}

# Vault KV fragments (parsed by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
variable "secrets" {
  type      = any
  default   = {}
  sensitive = true
}

variable "secret_files" {
  type      = any
  default   = {}
  sensitive = true
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
