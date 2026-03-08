variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "github_personal_access_token" {
  description = "GitHub personal access token used by the MCP server."
  type        = string
  sensitive   = true
}
