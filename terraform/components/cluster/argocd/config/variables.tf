# variables.tf
# External input contract for the Argo CD config slice.

variable "argocd_base_url" {
  description = "Argo CD API base URL (for example https://argocd.example.com)."
  type        = string
}

variable "argocd_api_token" {
  description = "Argo CD API token used by Terraform provider authentication."
  type        = string
  sensitive   = true
}

variable "argocd_insecure_skip_verify" {
  description = "Skip TLS certificate verification for Argo CD API calls."
  type        = bool
  default     = false
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
