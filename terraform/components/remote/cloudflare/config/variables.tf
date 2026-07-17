# variables.tf
# External input contract for the Cloudflare DNS config slice.

variable "provider_config" {
  description = "Provider configuration map for Cloudflare authentication."
  type        = any
}

variable "zone_id" {
  description = "Cloudflare zone ID that owns the DNS records."
  type        = string
}

variable "records" {
  description = "A records managed in Cloudflare."
  type = list(object({
    key     = string
    name    = string
    content = string
    ttl     = number
    proxied = bool
  }))
}

# Vault KV fragments (parsed by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
variable "secrets" {
  description = "Inline Vault KV secret fragments for vault_merge_config_secrets.py (not consumed by this Terraform root)."
  type        = any
  default     = {}
  sensitive   = true
}

variable "secret_files" {
  description = "Vault KV secret file path fragments for vault_merge_config_secrets.py (not consumed by this Terraform root)."
  type        = any
  default     = {}
  sensitive   = true
}
