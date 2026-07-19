# variables.tf
# External input contract for the Grafana Swarm app slice.

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

