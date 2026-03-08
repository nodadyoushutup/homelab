output "service_name" {
  description = "Docker Swarm service name for Vault"
  value       = docker_service.vault.name
}

output "service_id" {
  description = "Docker Swarm service ID for Vault"
  value       = docker_service.vault.id
}

output "network_name" {
  description = "Overlay network name used by Vault"
  value       = docker_network.vault.name
}

output "data_volume_name" {
  description = "Docker volume name backing Vault raft data"
  value       = docker_volume.vault_data.name
}

output "server_config_name" {
  description = "Docker config object name for Vault server configuration"
  value       = docker_config.vault_server.name
}

output "api_addr" {
  description = "Advertised Vault API address"
  value       = var.api_addr
}

output "published_port" {
  description = "Published host port used for Vault HTTP/UI"
  value       = var.published_port
}
