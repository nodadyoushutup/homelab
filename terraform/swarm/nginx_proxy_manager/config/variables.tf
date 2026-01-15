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

variable "default_certificate_email" {
  description = "Default Let's Encrypt email address for certificates"
  type        = string
  default     = null
}

variable "default_dns_challenge" {
  description = "Default DNS challenge settings applied when certificates omit explicit values"
  type = object({
    enabled             = optional(bool)
    provider            = optional(string)
    credentials         = optional(string)
    propagation_seconds = optional(number)
  })
  default = null
}

variable "certificates" {
  description = "Certificate configuration entries for Nginx Proxy Manager"
  type = list(object({
    name                     = string
    domain_names             = list(string)
    request_le               = optional(bool, true)
    email_address            = optional(string)
    dns_challenge            = optional(bool)
    dns_provider             = optional(string)
    dns_provider_credentials = optional(string)
    propagation_seconds      = optional(number)
  }))
  default = []

  validation {
    condition = (
      var.default_certificate_email != null ||
      alltrue([
        for cert in coalesce(var.certificates, []) :
        (!try(cert.request_le, true)) || cert.email_address != null
      ])
    )
    error_message = "Set default_certificate_email or provide email_address for every Let's Encrypt certificate."
  }
}

variable "proxy_hosts" {
  description = "Proxy host entries to create in Nginx Proxy Manager"
  type = list(object({
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
  }))
  default = []
}

variable "access_lists" {
  description = "Access list definitions for Nginx Proxy Manager"
  type = list(object({
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
  }))
  default = []
}

variable "streams" {
  description = "Stream entries for Nginx Proxy Manager (placeholder)"
  type        = list(any)
  default     = []
}

variable "redirections" {
  description = "Redirection entries for Nginx Proxy Manager (placeholder)"
  type        = list(any)
  default     = []
}

variable "remote_state_backend" {
  description = "Backend configuration map (converted from ~/.tfvars/minio.backend.hcl) for reading the app stage state."
  type        = any
}
