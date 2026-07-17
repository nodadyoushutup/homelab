# locals.tf
# Single source of truth for Proxmox VM/cloud-init values (resources read local.* only).

locals {
  provider_config = var.provider_config

  runner_amd64_user_config_path    = var.runner_amd64_user_config_path
  runner_amd64_network_config_path = var.runner_amd64_network_config_path

  k8s_cp_0_user_config_path    = var.k8s_cp_0_user_config_path
  k8s_cp_0_network_config_path = var.k8s_cp_0_network_config_path

  k8s_wk_0_user_config_path    = var.k8s_wk_0_user_config_path
  k8s_wk_0_network_config_path = var.k8s_wk_0_network_config_path

  k8s_wk_1_user_config_path    = var.k8s_wk_1_user_config_path
  k8s_wk_1_network_config_path = var.k8s_wk_1_network_config_path

  k8s_wk_2_user_config_path    = var.k8s_wk_2_user_config_path
  k8s_wk_2_network_config_path = var.k8s_wk_2_network_config_path

  k8s_wk_3_user_config_path    = var.k8s_wk_3_user_config_path
  k8s_wk_3_network_config_path = var.k8s_wk_3_network_config_path

  k8s_wk_4_user_config_path    = var.k8s_wk_4_user_config_path
  k8s_wk_4_network_config_path = var.k8s_wk_4_network_config_path

  k8s_wk_5_user_config_path    = var.k8s_wk_5_user_config_path
  k8s_wk_5_network_config_path = var.k8s_wk_5_network_config_path

  k8s_wk_6_user_config_path    = var.k8s_wk_6_user_config_path
  k8s_wk_6_network_config_path = var.k8s_wk_6_network_config_path

  k8s_wk_7_user_config_path    = var.k8s_wk_7_user_config_path
  k8s_wk_7_network_config_path = var.k8s_wk_7_network_config_path

  k8s_wk_8_user_config_path    = var.k8s_wk_8_user_config_path
  k8s_wk_8_network_config_path = var.k8s_wk_8_network_config_path

  k8s_wk_9_user_config_path    = var.k8s_wk_9_user_config_path
  k8s_wk_9_network_config_path = var.k8s_wk_9_network_config_path

  k8s_wk_10_user_config_path    = var.k8s_wk_10_user_config_path
  k8s_wk_10_network_config_path = var.k8s_wk_10_network_config_path
}
