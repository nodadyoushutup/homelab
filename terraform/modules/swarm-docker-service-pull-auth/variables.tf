variable "image_reference" {
  description = "Full image ref for the Swarm service (used to pick which registry credential applies)."
  type        = string
}

variable "registry_auths" {
  description = "Registry credential list from swarm_docker_provider_config (same shape as docker provider registry_auth)."
  type        = list(any)
  default     = []
}
