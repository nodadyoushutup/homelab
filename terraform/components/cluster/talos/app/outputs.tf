# outputs.tf
# Exposes talosconfig/kubeconfig content and their local output file paths.

output "talosconfig" {
  description = "Rendered Talos client configuration (talosconfig) for the cluster."
  value       = data.talos_client_configuration.cluster.talos_config
  sensitive   = true
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig YAML for the Kubernetes API."
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "kubernetes_client_configuration" {
  description = "Structured Kubernetes client configuration from the Talos kubeconfig resource."
  value       = talos_cluster_kubeconfig.cluster.kubernetes_client_configuration
  sensitive   = true
}

output "talosconfig_output_path" {
  description = "Local filesystem path where talosconfig was written, or null when disabled."
  value       = try(local_sensitive_file.talosconfig[0].filename, null)
}

output "kubeconfig_output_path" {
  description = "Local filesystem path where kubeconfig was written, or null when disabled."
  value       = try(local_sensitive_file.kubeconfig[0].filename, null)
}
