# variables.tf
# External input contract for the GHA runner (AMD64) Docker app slice.

variable "env" {
  description = "Container environment variables (components/swarm/nfs.tfvars and slice tfvars). GH_RUNNER_NAME is set per replica in main.tf."
  type        = map(string)
  sensitive   = true
}

variable "replicas" {
  description = "Number of runner containers on the pool host."
  type        = number
  default     = 4
}


variable "dns_nameservers" {
  description = "DNS nameservers for container DNS."
  type        = list(string)
  sensitive   = true
}


variable "nfs" {
  description = "Homelab repo NFS mount (components/swarm/nfs.tfvars)."
  type = object({
    target         = string
    driver_options = map(string)
  })
  sensitive = true
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the pool host."
  type        = any
}
