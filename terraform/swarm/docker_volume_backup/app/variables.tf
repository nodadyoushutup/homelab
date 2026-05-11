variable "provider_config" {
  description = "Configuration map passed to the Docker provider"
  type        = any

  default     = {}
}

variable "env" {
  description = "Environment variables passed to the docker-volume-backup container"
  type        = map(string)
  default     = {}
}

variable "backup_mounts" {
  description = "Map of backup mounts where each object defines source volume and target path"
  type = map(object({
    source    = string
    target    = string
    type      = optional(string, "volume")
    read_only = optional(bool, true)
  }))
  default = {}
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/config/providers/docker.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
    Merged with provider_config; per-stack tfvars override on key collision.
  EOT
  type        = any
  default     = {}
}

locals {
  provider_config = merge(var.swarm_docker_provider_config, var.provider_config)
  docker_registry_auths = (
    try(local.provider_config.registry_auths, null) != null
    ? local.provider_config.registry_auths
    : (
      try(local.provider_config.registry_auth, null) != null
      ? [local.provider_config.registry_auth]
      : []
    )
  )
}

