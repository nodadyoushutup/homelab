# variables.tf
# External input contract for the mcp-agentmemory Swarm app slice.

variable "env" {
  description = "Shared container environment (AGENTMEMORY_SECRET, MCP_AGENTMEMORY_API_KEY, optional overrides)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "replicas" {
  description = "Number of Swarm service replicas for each service."
  type        = number
  default     = 1
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

variable "docker_providers" {
  description = "Shared Docker provider catalog (map keyed by machine name); config-id terraform/providers/docker."
  type        = any
}

variable "registry_auths" {
  description = "Shared container registry auths reused by every Swarm slice."
  type        = any
  default     = []
}

variable "docker_machine" {
  description = "Which docker_providers entry this slice connects through."
  type        = string
}
