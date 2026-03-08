variable "provider_config" {
  description = "Provider configuration map for Cloudflare authentication."
  type        = any
}

variable "zone_id" {
  description = "Cloudflare zone ID that owns the DNS records."
  type        = string
}

variable "records" {
  description = "DNS records managed in Cloudflare."
  type = list(object({
    key       = string
    record_id = string
    name      = string
    type      = string
    content   = string
    ttl       = number
    proxied   = bool
    priority  = optional(number)
  }))
}
