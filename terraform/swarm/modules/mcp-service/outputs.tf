output "service_name" {
  description = "Docker Swarm service name."
  value       = docker_service.this.name
}

output "network_name" {
  description = "Docker Swarm overlay network name."
  value       = docker_network.this.name
}

output "mcp_url" {
  description = "HTTP MCP endpoint URL on the Swarm ingress network."
  value       = "http://${var.endpoint_host}:${var.published_port}/mcp"
}

output "published_port" {
  description = "Published Swarm ingress port."
  value       = var.published_port
}
