variable "service_name" {
  description = "Docker Swarm service name."
  type        = string
}

variable "network_name" {
  description = "Overlay network name. Defaults to the service name."
  type        = string
  default     = null
}

variable "image_reference" {
  description = "Container image reference to run."
  type        = string
}

variable "registry_address" {
  description = "Registry address used for service-level image pull auth."
  type        = string
  default     = null
}

variable "registry_auth" {
  description = "Optional service-level registry auth object with address, username, and password."
  type        = any
  default     = null
  sensitive   = true
}

variable "internal_port" {
  description = "Container TCP port exposed by the MCP HTTP server."
  type        = number
}

variable "published_port" {
  description = "Swarm ingress TCP port published for the MCP HTTP server."
  type        = number
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
}

variable "replicas" {
  description = "Number of Swarm replicas."
  type        = number
  default     = 1
}

variable "placement_constraints" {
  description = "Swarm placement constraints."
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

variable "command" {
  description = "Optional container command override."
  type        = list(string)
  default     = null
}

variable "args" {
  description = "Optional container args."
  type        = list(string)
  default     = null
}

variable "env" {
  description = "Environment variables passed to the container."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "user" {
  description = "Optional user or UID[:GID] to run as."
  type        = string
  default     = null
}

variable "cap_drop" {
  description = "Linux capabilities to drop."
  type        = list(string)
  default     = null
}

variable "mounts" {
  description = "Container mounts."
  type = list(object({
    type      = string
    source    = string
    target    = string
    read_only = optional(bool)
  }))
  default = []
}

variable "healthcheck" {
  description = "Optional Docker healthcheck payload."
  type = object({
    test         = list(string)
    interval     = optional(string)
    timeout      = optional(string)
    retries      = optional(number)
    start_period = optional(string)
  })
  default = null
}
