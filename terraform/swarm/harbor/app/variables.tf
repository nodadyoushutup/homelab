variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts + optional registry auth)."
  type        = any

  default = {}
}

variable "node_constraint" {
  description = "Swarm placement constraint for Harbor services."
  type        = string
  default     = "node.labels.role==swarm-cp-0"
}

variable "platform_architecture" {
  description = "CPU architecture for Harbor service placement."
  type        = string
  default     = "aarch64"
}

variable "network_name" {
  description = "Overlay network name for Harbor services."
  type        = string
  default     = "harbor"
}

variable "harbor_install_path" {
  description = "Absolute host path on the swarm node where Harbor install/config files exist."
  type        = string
  default     = "/mnt/eapp/harbor-manual/harbor"
}

variable "harbor_data_path" {
  description = "Absolute host path on the swarm node for Harbor persistent runtime data."
  type        = string
  default     = "/mnt/eapp/harbor-manual/data"
}

variable "harbor_log_path" {
  description = "Absolute host path on the swarm node for Harbor rsyslog log files."
  type        = string
  default     = "/mnt/eapp/harbor-manual/log"
}

variable "proxy_published_port" {
  description = "Published Swarm port for Harbor HTTP ingress (nginx proxy target is 8080)."
  type        = number
  default     = 35080
}

variable "log_syslog_published_port" {
  description = "Host-mode published port used by harbor-log syslog receiver (target 10514)."
  type        = number
  default     = 1514
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

variable "images" {
  description = "Container image references for Harbor runtime components."
  type = object({
    log           = string
    registry      = string
    registryctl   = string
    db            = string
    core          = string
    portal        = string
    jobservice    = string
    redis         = string
    proxy         = string
    trivy_adapter = string
  })
  default = {
    log           = "ghcr.io/nodadyoushutup/harbor-log:0.0.1@sha256:cfcb4497d9c42eb21a91cc92e2b92033809ddaab9f5b3ff32b98af01e0ffcd2b"
    registry      = "ghcr.io/nodadyoushutup/registry-photon:0.0.1@sha256:c39b686661967449659425b8752756c81dc6697b48595659181e4c2e61c0dbc4"
    registryctl   = "ghcr.io/nodadyoushutup/harbor-registryctl:0.0.1@sha256:bc42ae9c1b5853717da9adcbd3ff828b2d5b8fc84377aa86417eb63206a1cb7b"
    db            = "ghcr.io/nodadyoushutup/harbor-db:0.0.1@sha256:2050cd2a872015c4ec328e808b40084d7172e9610debb2036a9c0dbcc05e172d"
    core          = "ghcr.io/nodadyoushutup/harbor-core:0.0.1@sha256:0503ee3e98987c57a7ddf5557580208955aade3e6642a5063b7cabd62db69494"
    portal        = "ghcr.io/nodadyoushutup/harbor-portal:0.0.1@sha256:a695da7e1332848e23a10b455abe70e512083b81651f226d1ca76a9df30dde12"
    jobservice    = "ghcr.io/nodadyoushutup/harbor-jobservice:0.0.1@sha256:f1d1f7e45232ccff44b2f3ce53ab8b5b6a4d18af41d5ee4112cd52a8d9a1e525"
    redis         = "ghcr.io/nodadyoushutup/redis-photon:0.0.1@sha256:fa7ffbbdeb59390a45beac1af38969b1e24582490a2cb550fd1936c85a1ac295"
    proxy         = "ghcr.io/nodadyoushutup/nginx-photon:0.0.1@sha256:b85eb46199a1f8f4cc0c4c4985cbfdda8dfd37c5d3c95596bf6eb31e0f1e8628"
    trivy_adapter = "ghcr.io/nodadyoushutup/trivy-adapter-photon:0.0.1@sha256:daaaa8c06c597d88d5f11b677748f8128c96212bf3078b70fe269e4ad7e3596a"
  }
}

variable "env" {
  description = "Optional explicit env var maps per component (overrides env_file_paths for that component when non-empty)."
  type = object({
    db          = map(string)
    core        = map(string)
    registryctl = map(string)
    jobservice  = map(string)
    trivy       = map(string)
  })
  default = {
    db          = {}
    core        = {}
    registryctl = {}
    jobservice  = {}
    trivy       = {}
  }
}

variable "env_file_paths" {
  description = "Optional absolute local file paths on the Terraform runner for Harbor env files."
  type = object({
    db          = string
    core        = string
    registryctl = string
    jobservice  = string
    trivy       = string
  })
  default = {
    db          = ""
    core        = ""
    registryctl = ""
    jobservice  = ""
    trivy       = ""
  }
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/code/homelab/.config/terraform/providers/docker_arm64.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
    Merged with provider_config; per-stack tfvars override on key collision.
  EOT
  type        = any
  default     = {}
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
