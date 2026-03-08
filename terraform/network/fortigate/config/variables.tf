variable "provider_config" {
  description = "Provider/auth configuration for the fortios provider."
  type = object({
    fortigate = object({
      host      = string
      port      = optional(number)
      vdom      = optional(string)
      insecure  = optional(bool)
      api_token = optional(string)
      username  = optional(string)
      password  = optional(string)
    })
  })
  sensitive = true

  validation {
    condition = (
      try(trimspace(var.provider_config.fortigate.api_token), "") != "" ||
      (
        try(trimspace(var.provider_config.fortigate.username), "") != "" &&
        try(trimspace(var.provider_config.fortigate.password), "") != ""
      )
    )
    error_message = "Set provider_config.fortigate.api_token or both provider_config.fortigate.username and provider_config.fortigate.password."
  }
}

variable "config" {
  description = "Declarative FortiGate config payload sourced from tfvars."
  type        = any
}
