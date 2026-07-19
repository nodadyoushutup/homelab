# variables.tf
# External input contract for the FortiGate config slice.

variable "fortigate" {
  description = "FortiGate (fortios) provider login (config-id terraform/providers/fortigate); shared -var-file managed by the homelab-config web app."
  type = object({
    host      = string
    port      = optional(number)
    vdom      = optional(string)
    insecure  = optional(bool)
    api_token = optional(string)
    username  = optional(string)
    password  = optional(string)
  })
  sensitive = true

  validation {
    condition = (
      try(trimspace(var.fortigate.api_token), "") != "" ||
      (
        try(trimspace(var.fortigate.username), "") != "" &&
        try(trimspace(var.fortigate.password), "") != ""
      )
    )
    error_message = "Set fortigate.api_token or both fortigate.username and fortigate.password."
  }
}

variable "config" {
  description = "Declarative FortiGate config payload sourced from tfvars."
  type        = any
}

# Vault KV fragments (parsed by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
variable "secrets" {
  description = "Inline Vault KV secret fragments for vault_merge_config_secrets.py (not consumed by this Terraform root)."
  type        = any
  default     = {}
  sensitive   = true
}

variable "secret_files" {
  description = "Vault KV secret file path fragments for vault_merge_config_secrets.py (not consumed by this Terraform root)."
  type        = any
  default     = {}
  sensitive   = true
}
