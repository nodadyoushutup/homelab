variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "registry_auth" {
  description = "Optional registry auth for pulling the service image."
  type        = any
  default     = null
  sensitive   = true
}

variable "image_reference" {
  description = "Bash Pipeline MCP image to run."
  type        = string
  default     = "homelab/mcp-bash-pipeline:2026.04.17.1"
}

variable "env" {
  description = "Additional environment variables to pass to the container."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "published_port" {
  description = "Swarm ingress port exposed for the Bash Pipeline MCP HTTP endpoint."
  type        = number
  default     = 18203
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
  default     = "192.168.1.120"
}

variable "nfs_server" {
  description = "NFS server for homelab code and config exports."
  type        = string
  default     = "192.168.1.100"
}

variable "nfs_code_device" {
  description = "NFS export for repo code (mounted at /mnt/eapp/code in the task)."
  type        = string
  default     = ":/mnt/eapp/code"
}

variable "nfs_config_device" {
  description = "NFS export for shared config (mounted at /mnt/eapp/config in the task)."
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
