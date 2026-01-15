variable "provider_config" {
  description = "Configuration for the Docker provider"
  type        = any
}

variable "dns_nameservers" {
  description = "DNS nameservers to use in the Dozzle container"
  type        = list(string)
  default     = null
}

variable "placement" {
  description = "Placement configuration for the Dozzle service"
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}
