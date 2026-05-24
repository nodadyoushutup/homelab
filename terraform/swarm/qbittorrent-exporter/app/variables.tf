variable "endpoint_host" {
  description = "Host name used for Prometheus scrape target reporting."
  type        = string
  default     = "192.168.1.121"
}


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


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}
