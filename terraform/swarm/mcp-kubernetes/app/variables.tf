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
  description = "Kubernetes MCP image to run."
  type        = string
  default     = "quay.io/containers/kubernetes_mcp_server:v0.0.60@sha256:766a7282e0536d951d805f72b562d89707eefb84d35dcfd96e31c410071f6164"
}

variable "env" {
  description = "Additional environment variables to pass to the container."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "published_port" {
  description = "Swarm ingress port exposed for the Kubernetes MCP HTTP endpoint."
  type        = number
  default     = 18210
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
  default     = "192.168.1.120"
}

variable "kubeconfig_path" {
  description = "Host path to a kubeconfig with equivalent read-only access to the old in-cluster service account."
  type        = string
  default     = "/mnt/eapp/config/mcp-kubernetes/kubeconfig"
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
