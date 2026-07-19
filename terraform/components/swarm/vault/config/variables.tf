# variables.tf
# External input contract for the Vault config slice.

variable "vault" {
  description = "Vault provider login (config-id terraform/providers/vault); shared -var-file managed by the homelab-config web app."
  type = object({
    address         = string
    token           = string
    skip_tls_verify = optional(bool, false)
  })
  sensitive = true
}

variable "mount_path" {
  description = "Path where KV v2 will be mounted."
  type        = string
  default     = "secret"
}


variable "secret_files" {
  description = "Vault KV secret file paths for vault_merge_config_secrets.py."
  type        = map(map(map(string)))
  default     = {}

  validation {
    condition = alltrue([
      for group_name, _ in var.secret_files : can(regex("^[a-z0-9_-]+$", group_name))
    ])
    error_message = "Each secret_files group key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }

  validation {
    condition = alltrue(flatten([
      for _, grouped_entries in var.secret_files : [
        for secret_name, _ in grouped_entries : can(regex("^[a-z0-9_-]+$", secret_name))
      ]
    ]))
    error_message = "Each secret_files name key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }
}


variable "secrets" {
  description = "Vault KV secrets map for vault_merge_config_secrets.py."
  type        = map(map(map(string)))
  default     = {}

  validation {
    condition = alltrue([
      for group_name, _ in var.secrets : can(regex("^[a-z0-9_-]+$", group_name))
    ])
    error_message = "Each secrets group key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }

  validation {
    condition = alltrue(flatten([
      for _, grouped_entries in var.secrets : [
        for secret_name, _ in grouped_entries : can(regex("^[a-z0-9_-]+$", secret_name))
      ]
    ]))
    error_message = "Each secret name key must be lowercase alphanumeric plus '-' or '_' only. '/' is not allowed."
  }
}

