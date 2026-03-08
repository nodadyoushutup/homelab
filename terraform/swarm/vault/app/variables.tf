variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "dns_nameservers" {
  description = "DNS nameservers to use in the Vault container"
  type        = list(string)
  default     = null
}

variable "placement" {
  description = "Placement configuration for the Vault service"
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = {
    constraints = ["node.labels.role==swarm-cp-0"]
    platforms = [
      {
        os           = "linux"
        architecture = "aarch64"
      }
    ]
  }
}

variable "api_addr" {
  description = "Public API address Vault advertises"
  type        = string
  default     = "http://swarm-cp-0.local:8200"
}

variable "cluster_addr" {
  description = "Cluster address Vault advertises for raft communication"
  type        = string
  default     = "http://vault:8201"
}

variable "raft_node_id" {
  description = "Node identifier for Vault raft storage"
  type        = string
  default     = "vault-0"
}

variable "published_port" {
  description = "Published host port for Vault HTTP/UI traffic"
  type        = number
  default     = 8200
}
