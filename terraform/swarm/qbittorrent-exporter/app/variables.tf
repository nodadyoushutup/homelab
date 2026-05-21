variable "enable_high_cardinality" {
  description = "Per-torrent high-cardinality metrics (heavy; keep false for large libraries)."
  type        = bool
  default     = false
}


variable "enable_tracker" {
  description = "Export tracker-related metrics."
  type        = bool
  default     = true
}


variable "endpoint_host" {
  description = "Host name used for external URL reporting."
  type        = string
  default     = "192.168.1.121"
}


variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = {}
  sensitive   = true
}


variable "exporter_port_base" {
  description = "First host port for Prometheus scrape targets; each instance uses base + index (sorted instance name)."
  type        = number
  default     = 18300
}


variable "image_reference" {
  description = "Container image reference to deploy."
  type        = string
  default     = "ghcr.io/martabal/qbittorrent-exporter:v2.0.1"
}


variable "insecure_skip_verify" {
  description = "Skip TLS verification for qBittorrent Web UI HTTPS."
  type        = bool
  default     = true
}


variable "log_level" {
  description = "Exporter log level (INFO, DEBUG, WARN, ERROR)."
  type        = string
  default     = "INFO"
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

