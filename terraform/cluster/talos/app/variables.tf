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

variable "k8s_cp_0_node" { type = string }
variable "k8s_wk_0_node" { type = string }
variable "k8s_wk_1_node" { type = string }
variable "k8s_wk_2_node" { type = string }
variable "k8s_wk_3_node" { type = string }
variable "k8s_wk_4_node" { type = string }
variable "k8s_wk_5_node" { type = string }
variable "k8s_wk_6_node" { type = string }
variable "k8s_wk_7_node" { type = string }
variable "k8s_wk_8_node" { type = string }
variable "k8s_wk_9_node" { type = string }
variable "k8s_wk_10_node" { type = string }

# Talos config patch files per node (YAML docs in Talos patch format).
variable "k8s_cp_0_config_patch_paths" { type = list(string) }
variable "k8s_wk_0_config_patch_paths" { type = list(string) }
variable "k8s_wk_1_config_patch_paths" { type = list(string) }
variable "k8s_wk_2_config_patch_paths" { type = list(string) }
variable "k8s_wk_3_config_patch_paths" { type = list(string) }
variable "k8s_wk_4_config_patch_paths" { type = list(string) }
variable "k8s_wk_5_config_patch_paths" { type = list(string) }
variable "k8s_wk_6_config_patch_paths" { type = list(string) }
variable "k8s_wk_7_config_patch_paths" { type = list(string) }
variable "k8s_wk_8_config_patch_paths" { type = list(string) }
variable "k8s_wk_9_config_patch_paths" { type = list(string) }
variable "k8s_wk_10_config_patch_paths" { type = list(string) }

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
