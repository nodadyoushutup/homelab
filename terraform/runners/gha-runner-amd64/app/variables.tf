variable "env" {
  description = "Container environment variables (components/nfs.tfvars and slice tfvars). GH_RUNNER_NAME is set per replica in main.tf."
  type        = map(string)
  sensitive   = true
}


variable "image" {
  description = "GitHub Actions runner image reference."
  type        = string
  default     = "ghcr.io/nodadyoushutup/gha-runner:0.1.1"
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
  description = "Homelab repo NFS mount (components/nfs.tfvars)."
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
