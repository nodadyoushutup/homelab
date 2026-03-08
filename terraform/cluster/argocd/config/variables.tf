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
