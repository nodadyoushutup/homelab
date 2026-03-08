variable "provider_config" {
  description = "Authentication and connectivity inputs for the nginxproxymanager provider"
  type = object({
    nginx_proxy_manager = object({
      url          = string
      username     = string
      password     = optional(string)
      validate_tls = optional(bool)
    })
  })
}

variable "config" {
  description = "Declarative configuration for certificates, proxy hosts, and related resources"
  type = object({
    default_certificate_email = optional(string)
    default_dns_challenge = optional(object({
      enabled             = optional(bool)
      provider            = optional(string)
      credentials         = optional(string)
      propagation_seconds = optional(number)
    }))
    certificates = optional(list(object({
      name                     = string
      domain_names             = list(string)
      request_le               = optional(bool, true)
      email_address            = optional(string)
      dns_challenge            = optional(bool)
      dns_provider             = optional(string)
      dns_provider_credentials = optional(string)
      propagation_seconds      = optional(number)
    })), [])
    proxy_hosts = optional(list(object({
      name                    = string
      domain_names            = list(string)
      scheme                  = string
      forward_host            = string
      forward_port            = number
      certificate             = optional(string)
      access_list             = optional(string)
      block_exploits          = optional(bool, true)
      ssl_forced              = optional(bool, true)
      caching_enabled         = optional(bool, false)
      allow_websocket_upgrade = optional(bool, true)
      http2_support           = optional(bool, true)
      hsts_enabled            = optional(bool, false)
      hsts_subdomains         = optional(bool, false)
      access_list_id          = optional(number)
      advanced_config         = optional(string)
      locations = optional(list(object({
        path            = string
        scheme          = string
        forward_host    = string
        forward_port    = number
        advanced_config = optional(string)
      })), [])
    })), [])
    access_lists = optional(list(object({
      name        = string
      pass_auth   = optional(bool, true)
      satisfy_any = optional(bool, false)
      authorizations = optional(list(object({
        username = string
        password = string
      })), [])
      access = optional(list(object({
        directive = string
        address   = string
      })), [])
    })), [])
    streams      = optional(list(any), [])
    redirections = optional(list(any), [])
  })

  default = {
    default_certificate_email = null
    default_dns_challenge     = null
    certificates              = []
    proxy_hosts               = []
    access_lists              = []
    streams                   = []
    redirections              = []
  }

  validation {
    condition = (
      var.config.default_certificate_email != null ||
      alltrue([
        for cert in coalesce(var.config.certificates, []) :
        (!try(cert.request_le, true)) || cert.email_address != null
      ])
    )
    error_message = "Set config.default_certificate_email or provide email_address for every Let's Encrypt certificate."
  }
}

variable "app_state" {
  description = "Outputs from the app stage (remote state); used for documentation + future linkage"
  type        = any
  default     = null
}
