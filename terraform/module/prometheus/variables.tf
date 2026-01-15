variable "provider_config" {
  description = "Docker provider configuration"
  type        = any
}

variable "dns_nameservers" {
  description = "DNS nameservers to use in the Prometheus container"
  type        = list(string)
  default     = null
}

variable "placement" {
  description = "Placement configuration for the Prometheus service"
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}

variable "targets" {
  description = "Static scrape targets for the node_exporter job"
  type        = list(string)
  default     = null
}
