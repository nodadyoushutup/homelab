# variables.tf
# External input contract for the Graylog Swarm app slice.

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


variable "docker_providers" {
  description = "Shared Docker provider catalog (map keyed by machine name); config-id terraform/providers/docker."
  type        = any
}

variable "registry_auths" {
  description = "Shared container registry auths reused by every Swarm slice."
  type        = any
  default     = []
}

variable "docker_machine" {
  description = "Which docker_providers entry this slice connects through."
  type        = string
}

