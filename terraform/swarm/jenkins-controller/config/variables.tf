variable "provider_config" {
  description = "Provider configuration map containing Jenkins credentials."
  type        = any
}

variable "job_definition_root" {
  description = "Repo-relative root scanned for Jenkins pipeline definitions."
  type        = string
  default     = "pipelines"
}

variable "job_definition_glob" {
  description = "Glob matched beneath job_definition_root to discover Jenkins pipeline definitions."
  type        = string
  default     = "**/*.jenkins"
}

variable "github_repo_url" {
  description = "Git URL Jenkins should use when loading pipeline definitions from SCM."
  type        = string
  default     = "https://github.com/nodadyoushutup/homelab.git"
}

variable "github_repo_branch" {
  description = "Legacy single-branch pipeline input retained for tfvars compatibility. Multibranch jobs ignore this value."
  type        = string
  default     = "main"
}

variable "branch_discovery_includes" {
  description = "Space-separated wildcard branch patterns Jenkins should include when indexing multibranch jobs."
  type        = string
  default     = "*"
}

variable "branch_discovery_excludes" {
  description = "Space-separated wildcard branch patterns Jenkins should exclude when indexing multibranch jobs."
  type        = string
  default     = ""
}

variable "prune_dead_branches" {
  description = "Whether Jenkins should prune deleted branches from multibranch jobs."
  type        = bool
  default     = true
}

variable "orphaned_item_days_to_keep" {
  description = "Days to keep orphaned multibranch child jobs. Use -1 to keep indefinitely."
  type        = number
  default     = -1
}

variable "orphaned_item_num_to_keep" {
  description = "Number of orphaned multibranch child jobs to keep. Use -1 to keep indefinitely."
  type        = number
  default     = 20
}

variable "github_credentials_id" {
  description = "Existing or Terraform-managed Jenkins credentials ID used for private GitHub checkout."
  type        = string
  default     = ""
}

variable "manage_github_credentials" {
  description = "Whether this Terraform stage should create the Jenkins GitHub username/password credential."
  type        = bool
  default     = false
}

variable "github_credentials_username" {
  description = "GitHub username associated with the Jenkins checkout credential."
  type        = string
  default     = ""
}

variable "github_credentials_password" {
  description = "GitHub password or personal access token associated with the Jenkins checkout credential."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_credentials_description" {
  description = "Description stored with the managed GitHub Jenkins credential."
  type        = string
  default     = "Managed by Terraform for private GitHub pipeline checkout"
}

variable "github_credentials_scope" {
  description = "Scope assigned to the managed GitHub Jenkins credential."
  type        = string
  default     = "GLOBAL"
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
