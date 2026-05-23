variable "kubeconfig_path" {
  description = "Host path to the Kubernetes kubeconfig baked into a Swarm config."
  type        = string
}


variable "replicas" {
  description = "Number of Swarm service replicas."
  type        = number
  default     = 1
}


variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config."
  type        = list(string)
  sensitive   = true
}


variable "placement" {
  description = "Optional Swarm placement constraints and platforms."
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}
