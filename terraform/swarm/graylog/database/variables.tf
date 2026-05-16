variable "provider_config" {
  description = "Configuration for the Docker provider"
  type        = any

  default = {}
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in CONFIG_DIR/terraform/providers/docker_arm64.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
  EOT
  type        = any
  default     = {}
}

variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config."
  type        = list(string)
  sensitive   = true
}

variable "swarm_nfs_server" {
  type      = string
  default   = ""
  sensitive = true
}

variable "swarm_nfs_code_device" {
  type      = string
  sensitive = true
}

variable "swarm_nfs_config_device" {
  type      = string
  sensitive = true
}

variable "swarm_nfs_volume_type" {
  type      = string
  sensitive = true
}

variable "swarm_nfs_volume_o_rw" {
  type      = string
  sensitive = true
}

variable "swarm_nfs_volume_o_ro" {
  type      = string
  sensitive = true
}

variable "secrets" {
  type      = any
  default   = {}
  sensitive = true
}

variable "secret_files" {
  type      = any
  default   = {}
  sensitive = true
}
