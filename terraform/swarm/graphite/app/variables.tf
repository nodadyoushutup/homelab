variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type = object({
    docker = object({
      host     = string
      ssh_opts = optional(list(string))
    })
  })
}

variable "dns_nameservers" {
  description = "DNS nameservers to use in the Graphite container"
  type        = list(string)
  default     = null
}

variable "placement" {
  description = "Placement configuration for the Graphite service"
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}
