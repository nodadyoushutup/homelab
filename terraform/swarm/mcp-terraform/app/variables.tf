variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "toolsets" {
  description = "Comma-separated Terraform MCP toolsets to enable."
  type        = string
  default     = "registry"
}

variable "enable_tf_operations" {
  description = "Enable Terraform operation tools that require explicit approval."
  type        = bool
  default     = false
}

variable "tfe_address" {
  description = "Optional HCP Terraform or Terraform Enterprise address."
  type        = string
  default     = null
}

variable "tfe_token" {
  description = "Optional HCP Terraform or Terraform Enterprise API token."
  type        = string
  default     = null
  sensitive   = true
}

variable "mcp_allowed_origins" {
  description = "Optional comma-separated list of allowed browser origins for CORS."
  type        = string
  default     = null
}

variable "mcp_cors_mode" {
  description = "Terraform MCP CORS mode."
  type        = string
  default     = "strict"
}
