variable "provider_config" {
  description = "Provider configuration map passed to the Docker provider"
  type        = any
}

variable "env" {
  description = "Additional environment variables to pass to the Nginx Proxy Manager container"
  type        = map(string)
  default     = null
}

variable "dns_nameservers" {
  description = "DNS nameservers to use in the Nginx Proxy Manager container"
  type        = list(string)
  default     = null
}

variable "placement" {
  description = "Placement configuration for the Nginx Proxy Manager service"
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}
