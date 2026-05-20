variable "swarm_docker_provider_config" {
  description = <<-EOT
    Docker SSH host and registry_auths for the Swarm control plane.
    Set in CONFIG_DIR/terraform/providers/docker_arm64.tfvars (passed by pipelines/terraform/swarm/chromadb/app.sh).
  EOT
  type        = any
}

variable "replicas" {
  description = "Number of ChromaDB replicas to run. Keep at one for the local persistent volume."
  type        = number
  default     = 1
}

variable "placement" {
  description = "Swarm task placement (constraints and platforms). Omit in tfvars to skip placement in the task spec."
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}

variable "dns_nameservers" {
  description = <<-EOT
    DNS nameservers for Swarm task dns_config. Set only in
    CONFIG_DIR/terraform/providers/dns.tfvars (merged by pipelines/terraform/swarm/chromadb/app.sh).
  EOT
  type        = list(string)
  sensitive   = true
}
