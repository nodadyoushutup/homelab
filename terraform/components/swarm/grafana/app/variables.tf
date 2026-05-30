variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = null
}


variable "ini_path" {
  description = "Host path to grafana.ini bind-mounted into Grafana."
  type        = string
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

