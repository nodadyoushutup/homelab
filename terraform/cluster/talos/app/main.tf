locals {
  bootstrap_node   = var.provider_config.talos.bootstrap_node
  talos_endpoint   = var.provider_config.talos.endpoint
  client_endpoints = var.client_endpoints

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
    var.k8s_cp_0_node,
    var.k8s_wk_0_node,
    var.k8s_wk_1_node,
    var.k8s_wk_2_node,
    var.k8s_wk_3_node,
    var.k8s_wk_4_node,
    var.k8s_wk_5_node,
    var.k8s_wk_6_node,
    var.k8s_wk_7_node,
    var.k8s_wk_8_node,
    var.k8s_wk_9_node,
    var.k8s_wk_10_node,
  ]
}

resource "talos_machine_secrets" "cluster" {
  talos_version = try(var.provider_config.talos.talos_version, null)
}

data "talos_machine_configuration" "k8s_cp_0" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_cp_0], [for p in var.k8s_cp_0_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_0" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_0], [for p in var.k8s_wk_0_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_1" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_1], [for p in var.k8s_wk_1_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_2" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_2], [for p in var.k8s_wk_2_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_3" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_3], [for p in var.k8s_wk_3_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_4" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_4], [for p in var.k8s_wk_4_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_5" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_5], [for p in var.k8s_wk_5_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_6" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_6], [for p in var.k8s_wk_6_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_7" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_7], [for p in var.k8s_wk_7_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_8" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_8], [for p in var.k8s_wk_8_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_9" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_9], [for p in var.k8s_wk_9_config_patch_paths : file(p)])
}

data "talos_machine_configuration" "k8s_wk_10" {
  cluster_name       = var.provider_config.talos.cluster_name
  cluster_endpoint   = var.provider_config.talos.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = try(var.provider_config.talos.talos_version, null)
  kubernetes_version = try(var.provider_config.talos.kubernetes_version, null)
  config_patches     = concat([local.hostname_config_patches.k8s_wk_10], [for p in var.k8s_wk_10_config_patch_paths : file(p)])
}

resource "talos_machine_configuration_apply" "k8s_cp_0" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_cp_0.machine_configuration
  endpoint                    = var.k8s_cp_0_node
  node                        = var.k8s_cp_0_node
}

resource "talos_machine_configuration_apply" "k8s_wk_0" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_0.machine_configuration
  endpoint                    = var.k8s_wk_0_node
  node                        = var.k8s_wk_0_node
}

resource "talos_machine_configuration_apply" "k8s_wk_1" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_1.machine_configuration
  endpoint                    = var.k8s_wk_1_node
  node                        = var.k8s_wk_1_node
}

resource "talos_machine_configuration_apply" "k8s_wk_2" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_2.machine_configuration
  endpoint                    = var.k8s_wk_2_node
  node                        = var.k8s_wk_2_node
}

resource "talos_machine_configuration_apply" "k8s_wk_3" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_3.machine_configuration
  endpoint                    = var.k8s_wk_3_node
  node                        = var.k8s_wk_3_node
}

resource "talos_machine_configuration_apply" "k8s_wk_4" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_4.machine_configuration
  endpoint                    = var.k8s_wk_4_node
  node                        = var.k8s_wk_4_node
}

resource "talos_machine_configuration_apply" "k8s_wk_5" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_5.machine_configuration
  endpoint                    = var.k8s_wk_5_node
  node                        = var.k8s_wk_5_node
}

resource "talos_machine_configuration_apply" "k8s_wk_6" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_6.machine_configuration
  endpoint                    = var.k8s_wk_6_node
  node                        = var.k8s_wk_6_node
}

resource "talos_machine_configuration_apply" "k8s_wk_7" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_7.machine_configuration
  endpoint                    = var.k8s_wk_7_node
  node                        = var.k8s_wk_7_node
}

resource "talos_machine_configuration_apply" "k8s_wk_8" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_8.machine_configuration
  endpoint                    = var.k8s_wk_8_node
  node                        = var.k8s_wk_8_node
}

resource "talos_machine_configuration_apply" "k8s_wk_9" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_9.machine_configuration
  endpoint                    = var.k8s_wk_9_node
  node                        = var.k8s_wk_9_node
}

resource "talos_machine_configuration_apply" "k8s_wk_10" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8s_wk_10.machine_configuration
  endpoint                    = var.k8s_wk_10_node
  node                        = var.k8s_wk_10_node
}

resource "talos_machine_bootstrap" "cluster" {
  depends_on = [talos_machine_configuration_apply.k8s_cp_0]

  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoint             = local.talos_endpoint
  node                 = local.bootstrap_node
}

resource "talos_cluster_kubeconfig" "cluster" {
  depends_on = [talos_machine_bootstrap.cluster]

  client_configuration         = talos_machine_secrets.cluster.client_configuration
  endpoint                     = local.talos_endpoint
  node                         = local.bootstrap_node
  certificate_renewal_duration = try(var.provider_config.talos.kubeconfig_renewal, null)
}

data "talos_client_configuration" "cluster" {
  cluster_name         = var.provider_config.talos.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = local.client_endpoints
  nodes                = local.client_nodes
}

resource "local_sensitive_file" "talosconfig" {
  count                = var.talosconfig_output_path == "" ? 0 : 1
  filename             = var.talosconfig_output_path
  content              = data.talos_client_configuration.cluster.talos_config
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_sensitive_file" "kubeconfig" {
  count                = var.kubeconfig_output_path == "" ? 0 : 1
  filename             = var.kubeconfig_output_path
  content              = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  file_permission      = "0600"
  directory_permission = "0700"
}

output "talosconfig" {
  value     = data.talos_client_configuration.cluster.talos_config
  sensitive = true
}

output "kubeconfig_raw" {
  value     = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive = true
}

output "kubernetes_client_configuration" {
  value     = talos_cluster_kubeconfig.cluster.kubernetes_client_configuration
  sensitive = true
}

output "talosconfig_output_path" {
  value = try(local_sensitive_file.talosconfig[0].filename, null)
}

output "kubeconfig_output_path" {
  value = try(local_sensitive_file.kubeconfig[0].filename, null)
}
