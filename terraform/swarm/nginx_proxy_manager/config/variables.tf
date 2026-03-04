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
  type = string
}