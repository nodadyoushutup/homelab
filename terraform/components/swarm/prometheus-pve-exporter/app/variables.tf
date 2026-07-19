# variables.tf
# External input contract for the prometheus-pve-exporter Swarm app slice.

variable "disable_config_collector" {
  description = "Disable per-guest config collector (extra API calls per VM/CT)."
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
variable "published_port" {
  description = "Swarm ingress published port."
  type        = number
  default     = 9221
}


variable "pve_targets" {
  description = "Proxmox VE API hostnames or IPs scraped via /pve?target= (one cluster job per target)."
  type        = list(string)
  default     = ["192.168.1.10"]
}


variable "verify_ssl" {
  description = "When false, sets PVE_VERIFY_SSL=false for self-signed PVE API certificates."
  type        = bool
  default     = false
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

