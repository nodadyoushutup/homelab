# variables.tf
# External input contract for the qBittorrent exporter Swarm app slice.

variable "env" {
  description = "Container environment variables shared by all exporter instances."
  type        = map(string)
  default     = {}
  sensitive   = true
}


variable "instances" {
  description = "qBittorrent exporter instances keyed by overlay name (e.g. movie-0)."
  type = map(object({
    base_url       = string
    published_port = number
  }))
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
