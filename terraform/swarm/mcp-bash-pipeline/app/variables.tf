variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "repo_mount_path" {
  description = "Absolute host path to the shared code tree mounted into the container."
  type        = string
}

variable "tfvars_mount_path" {
  description = "Absolute host path to the tfvars tree mounted into the container."
  type        = string
}

variable "workspace_root" {
  description = "Default absolute workspace root inside the container."
  type        = string
}

variable "workspace_allowed_roots" {
  description = "Colon-separated absolute allowed workspace roots inside the container."
  type        = string
  default     = "/mnt/eapp/code"
}

variable "workspace_name" {
  description = "Default logical workspace name carried through the request header."
  type        = string
  default     = "homelab"
}

variable "runtime_uid" {
  description = "UID used to run the container process."
  type        = number
}

variable "runtime_gid" {
  description = "GID used to run the container process."
  type        = number
}

variable "default_timeout_seconds" {
  description = "Default timeout for synchronous pipeline execution."
  type        = number
  default     = 1800
}

variable "max_output_chars" {
  description = "Maximum stdout/stderr characters returned by one pipeline run."
  type        = number
  default     = 12000
}
