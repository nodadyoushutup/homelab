output "service_id" {
  description = "ID of the Swarm service backing the Jenkins controller"
  value       = docker_service.controller.id
}

output "casc_config_sha" {
  description = "SHA-256 hash of the rendered Jenkins Configuration as Code payload"
  value       = local.casc_config_sha
}

output "controller_image" {
  description = "Container image (including digest) used by the Jenkins controller service"
  value       = docker_service.controller.task_spec[0].container_spec[0].image
}
