output "network_name" {
  description = "Overlay network name for the Zot service."
  value       = docker_network.zot.name
}

output "published_port" {
  description = "Swarm ingress port for Zot HTTP."
  value       = var.published_port
}

output "registry_url" {
  description = "Internal Swarm DNS URL for docker pull/push (http)."
  value       = "http://zot:${var.http_port}"
}

output "service_name" {
  description = "Swarm service name."
  value       = docker_service.zot.name
}

output "volume_name" {
  description = "Swarm volume backing Zot storage."
  value       = docker_volume.zot_data.name
}
