variable "config" {
  description = "Nginx Proxy Manager proxy host and certificate definitions."
  type        = any
}


variable "provider_config" {
  description = "Provider API URL and credentials for this config slice."
  type = object({
    nginx_proxy_manager = object({
      url          = string
      username     = string
      password     = optional(string)
      validate_tls = optional(bool)
    })
  })
}

