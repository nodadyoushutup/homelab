variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)"
  type        = any
}

variable "env" {
  description = "Environment variables to pass to the Grafana container"
  type        = map(string)
  default     = null
}

variable "dns_nameservers" {
  description = "DNS nameservers to use in the Grafana container"
  type        = list(string)
  default     = null
}

variable "placement" {
  description = "Placement configuration for the Grafana service"
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}
