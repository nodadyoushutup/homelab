variable "provider_config" {
  description = "Provider/auth configuration for the nginxproxymanager provider"
  type = object({
    nginx_proxy_manager = object({
      url          = string
      username     = string
      password     = optional(string)
      validate_tls = optional(bool)
    })
  })
}

variable "dns_provider_credentials" {
  description = "Legacy fallback Cloudflare credential token used only when var.config is unset"
  type        = string
  default     = null
}

variable "config" {
  description = "Declarative NPM config payload; when null, stack uses legacy built-in defaults"
  type        = any
  default     = null
}

variable "remote_state_backend" {
  description = "Backend config map used to load app-stage remote state"
  type        = any
  default     = null
}
