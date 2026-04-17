variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "repo_mount_path" {
  description = "Absolute host path for the shared code tree exposed to the git MCP server."
  type        = string
  default     = "/mnt/eapp/code"
}

variable "repository_root" {
  description = "Absolute in-container repository allowlist root exposed to git MCP tools."
  type        = string
  default     = "/mnt/eapp/code"
}

variable "runtime_uid" {
  description = "UID used inside the container so NFS-mounted git operations do not hit root_squash."
  type        = number
  default     = 1000
}

variable "runtime_gid" {
  description = "GID used inside the container so NFS-mounted git operations do not hit root_squash."
  type        = number
  default     = 1000
}
