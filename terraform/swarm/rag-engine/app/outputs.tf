output "service_name" {
  description = "Docker Swarm service name."
  value       = docker_service.rag_engine.name
}

output "rag_engine_url" {
  description = "HTTP RAG engine endpoint URL on the Swarm ingress network."
  value       = "http://${var.endpoint_host}:${var.published_port}"
}

output "published_port" {
  description = "Published Swarm ingress port."
  value       = var.published_port
}
