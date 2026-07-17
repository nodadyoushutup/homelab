# variables.tf
# External input contract for the Nginx Proxy Manager config slice.

variable "provider_config" {
  description = "Nginx Proxy Manager API URL and credentials for this config slice."
  type = object({
    url          = string
    username     = string
    password     = optional(string)
    validate_tls = optional(bool)
  })
}

variable "default" {
  description = "Defaults applied to Let's Encrypt certificates unless overridden per certificate."
  type = object({
    certificate_email = optional(string)
    dns_challenge = optional(object({
      enabled             = optional(bool)
      provider            = optional(string)
      credentials         = optional(string)
      propagation_seconds = optional(number)
    }))
  })
  default = {}
}

variable "certificates" {
  description = "Let's Encrypt certificate specs keyed by name (referenced from proxy_hosts, redirections, streams)."
  type        = any
  default     = {}
}

variable "access_lists" {
  description = "Nginx Proxy Manager access list definitions keyed by name."
  type        = any
  default     = {}
}

variable "proxy_hosts" {
  description = "HTTP(S) reverse proxy host definitions keyed by name."
  type        = any
  default     = {}
}

variable "redirections" {
  description = "HTTP redirection host definitions keyed by name."
  type        = any
  default     = {}
}

variable "streams" {
  description = "TCP/UDP stream forwarding definitions keyed by name."
  type        = any
  default     = {}
}
