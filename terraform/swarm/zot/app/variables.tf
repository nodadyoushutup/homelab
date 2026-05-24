variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config."
  type        = list(string)
  sensitive   = true
}


variable "enable_auth" {
  description = "When true, enable htpasswd auth using htpasswd_file_path."
  type        = bool
  default     = false
}


variable "enable_mgmt" {
  description = "Enable the Zot management API extension."
  type        = bool
  default     = true
}


variable "enable_search" {
  description = "Enable the Zot search extension (includes CVE metadata in full image)."
  type        = bool
  default     = true
}


variable "enable_ui" {
  description = "Enable the Zot web UI extension."
  type        = bool
  default     = true
}


variable "htpasswd_file_path" {
  description = "Absolute host path to an htpasswd file mounted at /etc/zot/htpasswd when enable_auth is true."
  type        = string
  default     = ""
}


variable "http_port" {
  description = "Container HTTP listen port for the Zot registry and UI."
  type        = number
  default     = 5000
}


variable "http_realm" {
  description = "HTTP auth realm presented to registry clients."
  type        = string
  default     = "zot"
}


variable "image" {
  description = "Full Zot container image reference (ghcr.io/project-zot/zot full build)."
  type        = string
  default     = "ghcr.io/project-zot/zot:v2.1.15@sha256:376cb38a335bab89571af306eff481547212746aff11828043c22f32637fe17b"
}


variable "log_level" {
  description = "Zot log level."
  type        = string
  default     = "info"
}


variable "network_name" {
  description = "Overlay network name for the Zot service."
  type        = string
  default     = "zot"
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


variable "published_port" {
  description = "Published Swarm ingress port for Zot HTTP (registry + UI)."
  type        = number
  default     = 35081
}


variable "storage_gc_delay" {
  description = "Delay before deleted blobs are eligible for garbage collection."
  type        = string
  default     = "1h"
}


variable "storage_gc_interval" {
  description = "Interval between Zot garbage collection runs."
  type        = string
  default     = "24h"
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}


variable "volume_name" {
  description = "Swarm local volume name for Zot registry storage."
  type        = string
  default     = "zot-data"
}
