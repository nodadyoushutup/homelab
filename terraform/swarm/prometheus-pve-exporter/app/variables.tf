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


variable "image_reference" {
  description = "Container image reference to deploy."
  type        = string
  default     = "prompve/prometheus-pve-exporter@sha256:4527b8080c4bd53ae8d7326ff7a3469dad0c1abb5753ff0bae9f1ef1c23cb2c9"
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


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

