variable "casc_config" {
  description = "Configuration as Code data structure for the Jenkins controller"
  type        = any
}

variable "mounts" {
  description = "Additional mount definitions appended to the baked Jenkins controller mounts"
  type = list(object({
    name        = string
    target      = string
    driver      = string
    driver_opts = map(string)
    no_copy     = bool
  }))
  default = []
}

variable "provider_config" {
  description = "Provider configuration shared across Jenkins resources"
  type        = any
}

variable "env" {
  description = "Additional environment variables to inject into the Jenkins controller task definition"
  type        = map(string)
  default     = {}
}
