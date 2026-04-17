variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "kubeconfig_file" {
  description = "Absolute local path on the Terraform runner to a dedicated kubeconfig, used to create a Docker secret."
  type        = string
}

variable "toolsets" {
  description = "Comma-separated Kubernetes MCP toolsets to enable."
  type        = string
  default     = "core,config"
}

variable "mcp_read_only" {
  description = "Whether to run kubernetes-mcp-server in read-only mode."
  type        = bool
  default     = true
}

variable "disable_multi_cluster" {
  description = "Whether to restrict the server to the current kubeconfig context only."
  type        = bool
  default     = true
}

variable "list_output" {
  description = "Output format for list operations."
  type        = string
  default     = "yaml"
}

variable "stateless" {
  description = "Whether to disable tool and prompt change notifications for containerized HTTP deployment."
  type        = bool
  default     = true
}
