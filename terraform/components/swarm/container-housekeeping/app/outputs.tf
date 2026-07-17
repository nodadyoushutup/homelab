# outputs.tf
# Exported Swarm service identifiers for container-housekeeping.

output "service_id" {
  description = "Swarm service ID for global container housekeeping."
  value       = docker_service.container_housekeeping.id
}

output "service_name" {
  description = "Swarm service name for global container housekeeping."
  value       = docker_service.container_housekeeping.name
}

output "wk4_service_id" {
  description = "Swarm service ID for swarm-wk-4 container housekeeping."
  value       = docker_service.container_housekeeping_wk4.id
}

output "wk4_service_name" {
  description = "Swarm service name for swarm-wk-4 container housekeeping."
  value       = docker_service.container_housekeeping_wk4.name
}
