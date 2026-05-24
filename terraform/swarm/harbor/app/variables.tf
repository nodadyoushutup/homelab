variable "env" {
  description = "Container environment variables."
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


variable "harbor_data_path" {
  description = "Absolute host path on the swarm node for Harbor persistent runtime data."
  type        = string
  default     = "/mnt/eapp/harbor-manual/data"
}


variable "harbor_install_path" {
  description = "Absolute host path on the swarm node where Harbor install/config files exist."
  type        = string
  default     = "/mnt/eapp/harbor-manual/harbor"
}


variable "harbor_log_path" {
  description = "Absolute host path on the swarm node for Harbor rsyslog log files."
  type        = string
  default     = "/mnt/eapp/harbor-manual/log"
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
    log           = "ghcr.io/nodadyoushutup/harbor-log:0.0.1"
    registry      = "ghcr.io/nodadyoushutup/harbor-registry-photon:0.0.1"
    registryctl   = "ghcr.io/nodadyoushutup/harbor-registryctl:0.0.1"
    db            = "ghcr.io/nodadyoushutup/harbor-db:0.0.1"
    core          = "ghcr.io/nodadyoushutup/harbor-core:0.0.1"
    portal        = "ghcr.io/nodadyoushutup/harbor-portal:0.0.1"
    jobservice    = "ghcr.io/nodadyoushutup/harbor-jobservice:0.0.1"
    redis         = "ghcr.io/nodadyoushutup/harbor-redis-photon:0.0.1"
    proxy         = "ghcr.io/nodadyoushutup/harbor-nginx-photon:0.0.1"
    trivy_adapter = "ghcr.io/nodadyoushutup/harbor-trivy-adapter-photon:0.0.1"
  }
}


variable "log_syslog_published_port" {
  description = "Host-mode published port used by harbor-log syslog receiver (target 10514)."
  type        = number
  default     = 1514
}


variable "network_name" {
  description = "Overlay network name for Harbor services."
  type        = string
  default     = "harbor"
}


variable "proxy_published_port" {
  description = "Published Swarm port for Harbor HTTP ingress (nginx proxy target is 8080)."
  type        = number
  default     = 35080
}


variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config."
  type        = list(string)
  sensitive   = true
}


variable "placement" {
  description = "Optional Swarm placement constraints and platforms."
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

