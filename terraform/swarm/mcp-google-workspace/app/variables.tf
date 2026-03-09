variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "workspace_delegated_user" {
  description = "Google Workspace user email to impersonate via domain-wide delegation."
  type        = string
}

variable "workspace_service_account_file" {
  description = "Absolute local path on the Terraform runner to service_account.json, used to create a Docker secret."
  type        = string
}

variable "workspace_tool_tier" {
  description = "Tool tier passed to workspace-mcp (--tool-tier)."
  type        = string
  default     = "complete"

  validation {
    condition     = contains(["core", "extended", "complete"], var.workspace_tool_tier)
    error_message = "workspace_tool_tier must be one of: core, extended, complete."
  }
}

variable "workspace_tools" {
  description = "Optional space-delimited tools list passed to --tools (for example: 'gmail drive calendar')."
  type        = string
  default     = null
}

variable "workspace_read_only" {
  description = "Whether to run workspace-mcp in read-only mode."
  type        = bool
  default     = false
}
