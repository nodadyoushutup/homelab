variable "swarm_docker_provider_config" {
  description = <<-EOT
    Docker SSH host and registry_auths for the Swarm control plane.
    Set in CONFIG_DIR/terraform/providers/docker_arm64.tfvars (passed by pipelines/terraform/swarm/chromadb/app.sh).
  EOT
  type        = any
}

variable "endpoint_host" {
  description = "Host used when reporting the external ChromaDB URL."
  type        = string
  default     = "192.168.1.120"
}

variable "replicas" {
  description = "Number of ChromaDB replicas to run. Keep at one for the local persistent volume."
  type        = number
  default     = 1
}

variable "placement_constraints" {
  description = "Swarm placement constraints for the ChromaDB service."
  type        = list(string)
  default     = ["node.labels.role==swarm-wk-4"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config. Set in app.tfvars."
  type        = list(string)
  sensitive   = true
}
