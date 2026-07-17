# variables.tf
# External input contract for the Vault Swarm app slice.

variable "api_addr" {
  description = "Public API address Vault advertises."
  type        = string
  default     = "http://swarm-cp-0.local:8200"
}


variable "cluster_addr" {
  description = "Cluster address Vault advertises for raft communication."
  type        = string
  default     = "http://vault:8201"
}


variable "published_port" {
  description = "Swarm ingress published port."
  type        = number
  default     = 8200
}


variable "raft_node_id" {
  description = "Node identifier for Vault raft storage."
  type        = string
  default     = "vault-0"
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

