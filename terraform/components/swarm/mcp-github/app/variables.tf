# variables.tf
# External input contract for the mcp-github Swarm app slice.

variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = {}
  sensitive   = true
}


variable "replicas" {
  description = "Number of Swarm service replicas."
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


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}
