variable "provider_config" {
  description = "Configuration for the Docker provider"
  type        = any

  default = {}
}

variable "env" {
  description = "Graylog and Data Node environment (secrets and HTTP external URI)."
  type = object({
    GRAYLOG_PASSWORD_SECRET     = string
    GRAYLOG_ROOT_PASSWORD_SHA2  = string
    GRAYLOG_HTTP_EXTERNAL_URI   = string
    GRAYLOG_MONGODB_URI         = optional(string)
    GRAYLOG_HTTP_BIND_ADDRESS   = optional(string)
  })
  sensitive = true
}

variable "published_port_ui" {
  description = "Swarm ingress port for Graylog web UI and API."
  type        = number
  default     = 9000
}

variable "published_port_syslog_tcp" {
  description = "Swarm ingress port for syslog (TCP) ingest."
  type        = number
  default     = 1514
}

variable "published_port_gelf_tcp" {
  description = "Swarm ingress port for GELF (TCP) ingest."
  type        = number
  default     = 12201
}

variable "swarm_docker_provider_config" {
  description = "Shared Docker SSH host and registry credentials."
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
