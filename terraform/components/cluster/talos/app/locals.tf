# locals.tf
# Single source of truth for Talos machine config/bootstrap/kubeconfig values (resources read local.* only).

locals {
  provider_config = var.provider_config

  bootstrap_node   = local.provider_config.talos.bootstrap_node
  talos_endpoint   = local.provider_config.talos.endpoint
  client_endpoints = var.client_endpoints

  talosconfig_output_path = var.talosconfig_output_path
  kubeconfig_output_path  = var.kubeconfig_output_path

  secrets      = var.secrets
  secret_files = var.secret_files

  k8s_cp_0_node  = var.k8s_cp_0_node
  k8s_wk_0_node  = var.k8s_wk_0_node
  k8s_wk_1_node  = var.k8s_wk_1_node
  k8s_wk_2_node  = var.k8s_wk_2_node
  k8s_wk_3_node  = var.k8s_wk_3_node
  k8s_wk_4_node  = var.k8s_wk_4_node
  k8s_wk_5_node  = var.k8s_wk_5_node
  k8s_wk_6_node  = var.k8s_wk_6_node
  k8s_wk_7_node  = var.k8s_wk_7_node
  k8s_wk_8_node  = var.k8s_wk_8_node
  k8s_wk_9_node  = var.k8s_wk_9_node
  k8s_wk_10_node = var.k8s_wk_10_node

  k8s_cp_0_config_patch_paths  = var.k8s_cp_0_config_patch_paths
  k8s_wk_0_config_patch_paths  = var.k8s_wk_0_config_patch_paths
  k8s_wk_1_config_patch_paths  = var.k8s_wk_1_config_patch_paths
  k8s_wk_2_config_patch_paths  = var.k8s_wk_2_config_patch_paths
  k8s_wk_3_config_patch_paths  = var.k8s_wk_3_config_patch_paths
  k8s_wk_4_config_patch_paths  = var.k8s_wk_4_config_patch_paths
  k8s_wk_5_config_patch_paths  = var.k8s_wk_5_config_patch_paths
  k8s_wk_6_config_patch_paths  = var.k8s_wk_6_config_patch_paths
  k8s_wk_7_config_patch_paths  = var.k8s_wk_7_config_patch_paths
  k8s_wk_8_config_patch_paths  = var.k8s_wk_8_config_patch_paths
  k8s_wk_9_config_patch_paths  = var.k8s_wk_9_config_patch_paths
  k8s_wk_10_config_patch_paths = var.k8s_wk_10_config_patch_paths

  hostname_config_patches = {
    k8s_cp_0  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-cp-0" })
    k8s_wk_0  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-0" })
    k8s_wk_1  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-1" })
    k8s_wk_2  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-2" })
    k8s_wk_3  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-3" })
    k8s_wk_4  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-4" })
    k8s_wk_5  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-5" })
    k8s_wk_6  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-6" })
    k8s_wk_7  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-7" })
    k8s_wk_8  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-8" })
    k8s_wk_9  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-9" })
    k8s_wk_10 = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-10" })
  }

  client_nodes = [
    local.k8s_cp_0_node,
    local.k8s_wk_0_node,
    local.k8s_wk_1_node,
    local.k8s_wk_2_node,
    local.k8s_wk_3_node,
    local.k8s_wk_4_node,
    local.k8s_wk_5_node,
    local.k8s_wk_6_node,
    local.k8s_wk_7_node,
    local.k8s_wk_8_node,
    local.k8s_wk_9_node,
    local.k8s_wk_10_node,
  ]
}
