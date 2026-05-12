variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any

  default = {}
}

variable "image_reference" {
  description = "Official Playwright MCP image to run."
  type        = string
  default     = "mcr.microsoft.com/playwright/mcp:latest"
}

variable "published_port" {
  description = "Swarm ingress port exposed for the Playwright MCP HTTP endpoint."
  type        = number
  default     = 8931
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
  default     = "192.168.1.120"
}

variable "replicas" {
  description = "Number of Playwright MCP replicas to run."
  type        = number
  default     = 1
}

variable "placement_constraints" {
  description = "Swarm placement constraints for the Playwright MCP service."
  type        = list(string)
  default     = ["node.labels.role==swarm-cp-0"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "allowed_hosts" {
  description = "Host headers accepted by the HTTP MCP server. Use [\"*\"] for internal-only wildcard access."
  type        = list(string)
  default     = ["*"]
}

variable "output_dir" {
  description = "Container path where Playwright MCP writes snapshots, logs, and other non-screenshot output files."
  type        = string
  default     = "/mnt/eapp/code/homelab/data/playwright"
}

variable "screenshot_dir" {
  description = "Container path used as the working directory so relative screenshot filenames are written here."
  type        = string
  default     = "/mnt/eapp/code/homelab/data/screenshots"
}

variable "nfs_server" {
  description = "NFS server for the homelab code export."
  type        = string
  default     = "192.168.1.100"
}

variable "nfs_code_device" {
  description = "NFS export for repo code (mounted at /mnt/eapp/code; output, screenshots, and config paths must live under it)."
  type        = string
  default     = ":/mnt/eapp/code"
}

variable "dns_nameservers" {
  description = "DNS nameservers used by the Playwright MCP task."
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

