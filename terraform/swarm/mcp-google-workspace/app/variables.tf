variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any

  default     = {}
}


variable "image_reference" {
  description = "Google Workspace MCP image to run."
  type        = string
  default     = "homelab/mcp-google-workspace:2026.03.09.1"
}

variable "env_file_path" {
  description = "Optional dotenv file containing Google Workspace MCP secrets and settings."
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
  description = "Swarm ingress port exposed for the Google Workspace MCP HTTP endpoint."
  type        = number
  default     = 18209
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
  default     = "192.168.1.120"
}

variable "service_account_container_path" {
  description = "Path inside the container to the service account JSON (under the NFS /mnt/eapp/config mount)."
  type        = string
  default     = "/mnt/eapp/config/mcp-google-workspace/service_account.json"
}

variable "nfs_server" {
  description = "NFS server for the shared config export."
  type        = string
  default     = "192.168.1.100"
}

variable "nfs_config_device" {
  description = "NFS export for shared config (mounted read-only at /mnt/eapp/config)."
  type        = string
  default     = ":/mnt/eapp/config"
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

