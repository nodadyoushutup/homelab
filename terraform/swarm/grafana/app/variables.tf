variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)"
  type        = any

  default     = {}
}

variable "env" {
  description = "Environment variables to pass to the Grafana container"
  type        = map(string)
  default     = null
}

variable "grafana_ini_path" {
  description = "Absolute path to grafana.ini stored outside the repo"
  type        = string
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

