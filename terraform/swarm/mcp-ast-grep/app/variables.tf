variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "repo_mount_path" {
  description = "Absolute host path for the homelab repo checkout mounted into the ast-grep container."
  type        = string
  default     = "/mnt/eapp/code/homelab"
}

variable "project_root" {
  description = "Absolute in-container project root exposed to ast-grep tools."
  type        = string
  default     = "/mnt/eapp/code/homelab"
}
