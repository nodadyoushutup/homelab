output "stack_namespace" {
  description = "Namespace reported by the app stage (useful for cross-linking dashboards/docs)"
  value       = local.stack_namespace
}

output "certificate_ids" {
  description = "Map of certificate names to their numeric identifiers"
  value       = local.certificate_ids
}

output "proxy_host_ids" {
  description = "Map of proxy host names to their numeric identifiers"
  value = {
    for name, resource in nginxproxymanager_proxy_host.this : name => resource.id
  }
}
