# variables.tf
# External input contract for the container-housekeeping Swarm app slice.

variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}
