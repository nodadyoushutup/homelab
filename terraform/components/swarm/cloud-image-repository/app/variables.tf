# variables.tf
# External input contract for the cloud-image-repository Swarm app slice.

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

variable "nfs" {
  description = "NFS export backing the served /data directory (data/packer). driver_options carry the Docker local-driver NFS mount opts (type/o/device)."
  type = object({
    driver_options = map(string)
  })
  sensitive = true
}
