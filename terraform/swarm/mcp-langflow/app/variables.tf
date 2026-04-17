variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "langflow_base_url" {
  description = "Base URL for the target Langflow deployment."
  type        = string
}

variable "langflow_api_key" {
  description = "API key used by the Langflow MCP wrapper to call Langflow."
  type        = string
  sensitive   = true
}

variable "langflow_timeout" {
  description = "Request timeout in milliseconds passed through to langflow-mcp-server."
  type        = number
  default     = 30000
}

variable "langflow_consolidated_tools" {
  description = "Whether to use the consolidated 15-tool mode instead of the full granular tool list."
  type        = bool
  default     = true
}

variable "enable_deprecated_tools" {
  description = "Whether deprecated compatibility tools remain enabled in the Langflow MCP wrapper."
  type        = bool
  default     = false
}
