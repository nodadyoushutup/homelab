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
  description = "Argo CD MCP image to run."
  type        = string
  default     = "ghcr.io/argoproj-labs/mcp-for-argocd:latest@sha256:ef703dc15d0534c5368f835ae4948ac212055a3486481a56b05e9eb042a4ea6f"
}

variable "env_file_path" {
  description = "Optional dotenv file containing Argo CD MCP secrets and settings."
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
  description = "Swarm ingress port exposed for the Argo CD MCP HTTP endpoint."
  type        = number
  default     = 18201
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
  default     = "192.168.1.120"
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
