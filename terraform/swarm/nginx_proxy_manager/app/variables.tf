variable "db_mysql_host" {
  description = "Internal MySQL hostname for NPM (defaults to Swarm service DNS name)."
  type        = string
  default     = "mysql"
}


variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = null
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

