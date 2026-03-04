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

# variable "certificate_dns_challenges" {
#   description = "Per-certificate DNS challenge settings. Intentionally explicit per certificate."
#   type = object({
#     ndysu = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     nodadyoushutup = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     irc = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     grafana = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     minio = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     prometheus = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     graphite = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     npm = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     dozzle = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#     tautulli = object({
#       email_address            = string
#       dns_challenge            = bool
#       dns_provider             = string
#       dns_provider_credentials = string
#       propagation_seconds      = number
#     })
#   })
# }

# variable "remote_state_backend" {
#   description = "Backend configuration map (converted from ~/.tfvars/minio.backend.hcl) for reading the app stage state."
#   type        = any
# }
