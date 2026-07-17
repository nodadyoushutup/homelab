# outputs.tf
# Exported Swarm service identifier for the Jenkins controller.

output "controller_service_id" {
  description = "Docker Swarm service ID for the Jenkins controller"
  value       = docker_service.jenkins_controller.id
}
