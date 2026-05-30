variable "env" {
  description = "Container environment variables."
  type = object({
    GRAYLOG_PASSWORD_SECRET    = string
    GRAYLOG_ROOT_PASSWORD_SHA2 = string
    GRAYLOG_HTTP_EXTERNAL_URI  = string
    GRAYLOG_MONGODB_URI        = optional(string)
    GRAYLOG_HTTP_BIND_ADDRESS  = optional(string)
  })
  sensitive = true
}


variable "published_port_gelf_tcp" {
  description = "Swarm ingress port for GELF (TCP) ingest."
  type        = number
  default     = 12201
}


variable "published_port_syslog_tcp" {
  description = "Swarm ingress port for syslog (TCP) ingest."
  type        = number
  default     = 1514
}


variable "published_port_ui" {
  description = "Swarm ingress port for Graylog web UI and API."
  type        = number
  default     = 9000
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

