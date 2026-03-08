output "controller_service_id" {
  description = "Docker Swarm service ID for the Jenkins controller"
  value       = module.controller.service_id
}

output "controller_image" {
  description = "Container image reference used by the Jenkins controller"
  value       = module.controller.controller_image
}
