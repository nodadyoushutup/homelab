variable "provider_config" {
  description = <<-EOT
    Docker remote (host + ssh_opts). Optional nested registry_auth feeds both the docker
    provider and the Swarm service image pull.
  EOT
  type        = any
  default     = {}
}

variable "image_reference" {
  description = "qbittorrent-metrics-exporter image to run."
  type        = string
  default     = "harbor.nodadyoushutup.com/homelab/qbittorrent-metrics-exporter:0.3.2-homelab"
}

variable "published_port" {
  description = "Swarm ingress port for Prometheus /metrics."
  type        = number
  default     = 18080
}

variable "endpoint_host" {
  description = "Host used when reporting the external metrics URL."
  type        = string
  default     = "192.168.1.120"
}

variable "replicas" {
  description = "Number of exporter replicas (keep at 1)."
  type        = number
  default     = 1
}

variable "placement_constraints" {
  description = "Swarm placement constraints for this service."
  type        = list(string)
  default     = ["node.labels.role==swarm-cp-0"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "scrape_interval_seconds" {
  description = "How often the exporter polls each qBittorrent Web UI (seconds)."
  type        = number
  default     = 120
}

variable "startup_delay_seconds" {
  description = "Delay before starting the exporter process (lets qBittorrent pods finish rolling)."
  type        = number
  default     = 300
}

variable "qbittorrent_hosts" {
  description = "Map of instance name to qBittorrent Web UI base URL (https://...). Merged over built-in defaults."
  type        = map(string)
  default     = {}
}

variable "log_level" {
  description = "RUST_LOG level for the exporter."
  type        = string
  default     = "info"
}

variable "env" {
  description = "Additional environment variables merged over defaults."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "dns_nameservers" {
  description = <<-EOT
    DNS nameservers for Swarm task dns_config. Set in CONFIG_DIR/terraform/providers/dns.tfvars.
  EOT
  type        = list(string)
  sensitive   = true
}

variable "swarm_nfs_server" {
  description = "Unused; satisfies shared Swarm variable merge."
  type        = string
  default     = ""
  sensitive   = true
}

variable "swarm_nfs_code_device" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_config_device" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_volume_type" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_volume_o_rw" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_volume_o_ro" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_docker_provider_config" {
  description = "Shared Docker SSH host and registry credentials."
  type        = any
  default     = {}
}

# Vault KV fragments (merged by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
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
