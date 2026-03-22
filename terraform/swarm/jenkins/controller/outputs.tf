output "controller_service_id" {
  description = "Docker Swarm service ID for the Jenkins controller"
  value       = docker_service.jenkins_controller.id
}

output "controller_image" {
  description = "Container image reference used by the Jenkins controller"
  value       = var.controller_image
}
