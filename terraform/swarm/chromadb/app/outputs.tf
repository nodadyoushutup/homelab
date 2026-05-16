output "service_name" {
  description = "Docker Swarm service name."
  value       = docker_service.chromadb.name
}

output "chromadb_url" {
  description = "HTTP ChromaDB endpoint URL on the Swarm ingress network."
  value       = "http://${var.endpoint_host}:${local.chromadb_published_port}"
}

output "published_port" {
  description = "Published Swarm ingress port."
  value       = local.chromadb_published_port
}

output "data_volume_name" {
  description = "Docker volume storing ChromaDB data."
  value       = docker_volume.chromadb_data.name
}
