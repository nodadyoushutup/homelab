variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "repo_mount_path" {
  description = "Absolute host path for the shared code tree mounted into the ast-grep container."
  type        = string
  default     = "/mnt/eapp/code"
}

variable "project_root" {
  description = "Absolute in-container project allowlist root exposed to ast-grep tools."
  type        = string
  default     = "/mnt/eapp/code"
}

variable "runtime_uid" {
  description = "UID used inside the container so NFS-mounted ast-grep reads do not rely on root access."
  type        = number
  default     = 1000
}

variable "runtime_gid" {
  description = "GID used inside the container so NFS-mounted ast-grep reads do not rely on root access."
  type        = number
  default     = 1000
}
