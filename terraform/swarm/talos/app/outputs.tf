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
