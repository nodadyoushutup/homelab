# variables.tf
# External input contract for the Talos machine config/bootstrap app slice.

variable "provider_config" {
  description = "Provider configuration map for Talos apply/bootstrap"
  type = object({
    talos = object({
      cluster_name       = string
      cluster_endpoint   = string
      endpoint           = string
      bootstrap_node     = string
      talos_version      = optional(string)
      kubernetes_version = optional(string)
      kubeconfig_renewal = optional(string)
    })
  })
}

variable "k8s_cp_0_node" {
  description = "Talos API endpoint/IP for control-plane node k8s-cp-0."
  type        = string
}
variable "k8s_wk_0_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-0."
  type        = string
}
variable "k8s_wk_1_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-1."
  type        = string
}
variable "k8s_wk_2_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-2."
  type        = string
}
variable "k8s_wk_3_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-3."
  type        = string
}
variable "k8s_wk_4_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-4."
  type        = string
}
variable "k8s_wk_5_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-5."
  type        = string
}
variable "k8s_wk_6_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-6."
  type        = string
}
variable "k8s_wk_7_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-7."
  type        = string
}
variable "k8s_wk_8_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-8."
  type        = string
}
variable "k8s_wk_9_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-9."
  type        = string
}
variable "k8s_wk_10_node" {
  description = "Talos API endpoint/IP for worker node k8s-wk-10."
  type        = string
}

# Talos config patch files per node (YAML docs in Talos patch format).
variable "k8s_cp_0_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-cp-0."
  type        = list(string)
}
variable "k8s_wk_0_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-0."
  type        = list(string)
}
variable "k8s_wk_1_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-1."
  type        = list(string)
}
variable "k8s_wk_2_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-2."
  type        = list(string)
}
variable "k8s_wk_3_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-3."
  type        = list(string)
}
variable "k8s_wk_4_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-4."
  type        = list(string)
}
variable "k8s_wk_5_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-5."
  type        = list(string)
}
variable "k8s_wk_6_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-6."
  type        = list(string)
}
variable "k8s_wk_7_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-7."
  type        = list(string)
}
variable "k8s_wk_8_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-8."
  type        = list(string)
}
variable "k8s_wk_9_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-9."
  type        = list(string)
}
variable "k8s_wk_10_config_patch_paths" {
  description = "Filesystem paths to Talos machine config patch YAML files for k8s-wk-10."
  type        = list(string)
}

variable "client_endpoints" {
  description = "Talos client endpoints"
  type        = list(string)
}

variable "talosconfig_output_path" {
  description = "Output path for Terraform-managed Talos client config. Empty string disables local file creation."
  type        = string
  default     = ""
}

variable "kubeconfig_output_path" {
  description = "Output path for Terraform-managed Kubernetes kubeconfig. Empty string disables local file creation."
  type        = string
  default     = ""
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
