variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)"
  type        = any

  default = {}
}

variable "env" {
  description = "Environment variables to pass to the Grafana container"
  type        = map(string)
  default     = null
}

variable "ini_path" {
  description = "Absolute path to grafana.ini stored outside the repo"
  type        = string
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/code/homelab/.config/terraform/providers/docker.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
    Merged with provider_config; per-stack tfvars override on key collision.
  EOT
  type        = any
  default     = {}
}

variable "dns_nameservers" {
  description = <<-EOT
    DNS nameservers for Swarm task dns_config. Shared values live in terraform/providers/dns.tfvars
    (merged by scripts/terraform/swarm_pipeline.sh when the file exists, before stack app.tfvars).
    Unused by this Grafana root today; declared so shared dns.tfvars does not error as undeclared.
  EOT
  type        = list(string)
  default = [
    "192.168.1.1",
    "1.1.1.1",
    "8.8.8.8",
  ]
}

# Vault KV fragments (parsed by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
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
