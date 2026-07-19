# variables.tf
# External input contract for the Argo CD config slice.

variable "argocd" {
  description = "Argo CD provider login (config-id terraform/providers/argocd); shared -var-file managed by the homelab-config web app."
  type = object({
    base_url             = string
    api_token            = string
    insecure_skip_verify = optional(bool, false)
  })
  sensitive = true
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
