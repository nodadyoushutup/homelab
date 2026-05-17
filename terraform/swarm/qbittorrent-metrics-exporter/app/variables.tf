variable "provider_config" {
  description = <<-EOT
    Docker remote (host + ssh_opts). Optional nested registry_auth feeds both the docker
    provider and the Swarm service image pull.
  EOT
  type        = any
  default     = {}
}

variable "image_reference" {
  description = "martabal/qbittorrent-exporter image (one Swarm service per qBittorrent instance)."
  type        = string
  default     = "ghcr.io/martabal/qbittorrent-exporter:v2.0.1"
}

variable "exporter_port_base" {
  description = "First host port for Prometheus scrape targets; each instance uses base + index (sorted instance name)."
  type        = number
  default     = 18300
}

variable "endpoint_host" {
  description = "Swarm ingress host for Prometheus scrape URLs."
  type        = string
  default     = "192.168.1.121"
}

variable "placement_constraints" {
  description = "Swarm placement constraints for exporter services."
  type        = list(string)
  default     = ["node.labels.role==swarm-wk-0"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "qbittorrent_hosts" {
  description = "Map of instance name to qBittorrent Web UI base URL (https://...). Merged over built-in defaults."
  type        = map(string)
  default     = {}
}

variable "qbittorrent_hosts_only" {
  description = "When non-empty, deploy exporters only for these instance keys (must exist in defaults or qbittorrent_hosts)."
  type        = set(string)
  default     = []
}

variable "qbittorrent_username" {
  description = "qBittorrent Web UI username for all instances."
  type        = string
  default     = "admin"
}

variable "enable_high_cardinality" {
  description = "Per-torrent high-cardinality metrics (heavy; keep false for large libraries)."
  type        = bool
  default     = false
}

variable "insecure_skip_verify" {
  description = "Skip TLS verification for qBittorrent Web UI HTTPS."
  type        = bool
  default     = true
}

variable "enable_tracker" {
  description = "Export tracker-related metrics."
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Exporter log level (INFO, DEBUG, WARN, ERROR)."
  type        = string
  default     = "INFO"
}

variable "env" {
  description = "Additional environment variables merged per instance (e.g. QBITTORRENT_PASSWORD)."
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
