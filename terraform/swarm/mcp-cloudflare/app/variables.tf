variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token used by the MCP server."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID used by the DNS MCP server."
  type        = string
}

variable "cloudflare_email" {
  description = "Optional Cloudflare email for compatibility with APIs expecting user context."
  type        = string
  default     = null
}
