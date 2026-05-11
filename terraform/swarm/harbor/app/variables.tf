variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts + optional registry auth)."
  type        = any

  default     = {}
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
  description = "DNS resolvers injected into Harbor containers."
  type        = list(string)
  default = [
    "192.168.1.1",
    "1.1.1.1",
    "8.8.8.8",
  ]
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
    log           = "goharbor/harbor-log:v2.14.2"
    registry      = "goharbor/registry-photon:v2.14.2"
    registryctl   = "goharbor/harbor-registryctl:v2.14.2"
    db            = "goharbor/harbor-db:v2.14.2"
    core          = "goharbor/harbor-core:v2.14.2"
    portal        = "goharbor/harbor-portal:v2.14.2"
    jobservice    = "goharbor/harbor-jobservice:v2.14.2"
    redis         = "goharbor/redis-photon:v2.14.2"
    proxy         = "goharbor/nginx-photon:v2.14.2"
    trivy_adapter = "goharbor/trivy-adapter-photon:v2.14.2"
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

