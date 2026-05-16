variable "provider_config" {
  description = "Docker provider map merged after swarm_docker_provider_config: pool `docker` host/ssh_opts, optional `registry_auths` / `registry_auth` (mirror docker_arm64.tfvars for pool pulls; live values in docker_swarm.tfvars for this stack)."
  type        = any

  default = {}
}

variable "url" {
  description = "GitHub repo or org URL for runner registration."
  type        = string
  default     = "__SET_ME__"
}

variable "registration_token" {
  description = "GitHub Actions runner registration token from UI/API."
  type        = string
  sensitive   = true
  default     = "__SET_ME__"
}

variable "access_token" {
  description = "Optional GitHub access token used to mint registration/remove tokens at runner startup (recommended for replicated runners)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "replicas" {
  description = "Number of runner containers on the pool host (see provider_config.docker in docker_swarm.tfvars)."
  type        = number
  default     = 2
}

variable "engine_visible_build_path" {
  description = <<-EOT
    Absolute path bind-mounted from the pool host into each runner container at the identical path.
    The container sets HARBOR_BUILD_TMP_PARENT to this value so Harbor clones (and any
    Makefile nested `docker run -v $PWD:$PWD`) live on the host filesystem visible to the
    Docker engine when the task only mounts /var/run/docker.sock.
    The directory must already exist on the pool host before apply.
    The entrypoint runs `mkdir -p` under that mount for job subdirs once the bind succeeds.
  EOT
  type        = string
  default     = "/var/lib/gha-runner-engine-build"
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/code/homelab/.config/terraform/providers/docker_arm64.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
    This ARM64 runner pipeline also merges docker_swarm.tfvars (`provider_config.docker` for the pool
    host plus the same `registry_auths` pattern as this file) before dns/nfs/stack tfvars.
    Merged with provider_config; per-stack tfvars override on key collision.
    For runner pools, override `docker` in provider_config so Terraform targets the pool host
    (standalone `docker_container`, not Swarm scheduling).
  EOT
  type        = any
  default     = {}
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
