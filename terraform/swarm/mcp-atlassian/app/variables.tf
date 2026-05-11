variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any

  default     = {}
}


variable "image_reference" {
  description = "MCP Atlassian image to run."
  type        = string
  default     = "homelab/mcp-atlassian:0.0.1"
}

variable "env_file_path" {
  description = "Optional dotenv file containing Atlassian MCP secrets and settings."
  type        = string
  default     = ""
}

variable "env" {
  description = "Additional environment variables to pass to the container."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "published_port" {
  description = "Swarm ingress port exposed for the Atlassian MCP HTTP endpoint."
  type        = number
  default     = 18200
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
  default     = "192.168.1.120"
}

variable "nfs_server" {
  description = "NFS server for the homelab code export."
  type        = string
  default     = "192.168.1.100"
}

variable "nfs_code_device" {
  description = "NFS export for repo code (mounted at /mnt/eapp/code; screenshots/exports live under homelab/data/...)."
  type        = string
  default     = ":/mnt/eapp/code"
}

variable "timezone" {
  description = "Container timezone."
  type        = string
  default     = "America/New_York"
}

variable "replicas" {
  description = "Number of MCP replicas to run."
  type        = number
  default     = 1
}

variable "placement_constraints" {
  description = "Swarm placement constraints for this MCP service."
  type        = list(string)
  default     = ["node.labels.role==swarm-cp-0"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "dns_nameservers" {
  description = "DNS nameservers used by the task."
  type        = list(string)
  default = [
    "192.168.1.1",
    "1.1.1.1",
    "8.8.8.8",
  ]
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

