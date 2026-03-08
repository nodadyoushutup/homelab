variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "argocd_base_url" {
  description = "Argo CD base URL (for example, https://argocd.example.com)."
  type        = string
}

variable "argocd_api_token" {
  description = "Argo CD API token used by the MCP server."
  type        = string
  sensitive   = true
}

variable "mcp_read_only" {
  description = "Enable read-only MCP mode (disables mutating tools)."
  type        = bool
  default     = true
}

variable "argocd_insecure_skip_verify" {
  description = "Disable TLS certificate verification for Argo CD API calls."
  type        = bool
  default     = false
}
