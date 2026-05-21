variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = {}
  sensitive   = true
}


variable "image_reference" {
  description = "Container image reference to deploy."
  type        = string
  default     = "homelab/mcp-bash-pipeline:2026.04.17.1"
}


variable "published_port" {
  description = "Swarm ingress published port."
  type        = number
  default     = 18203
}


variable "replicas" {
  description = "Number of Swarm service replicas."
  type        = number
  default     = 1
}


variable "timezone" {
  description = "Container TZ environment value."
  type        = string
  default     = "America/New_York"
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


variable "swarm_nfs_code_device" {
  description = "NFS export for homelab code (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_nfs_config_device" {
  description = "NFS export for homelab config (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_nfs_volume_type" {
  description = "Docker volume driver type for NFS mounts (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_nfs_volume_o_rw" {
  description = "Read-write NFS volume mount options (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_nfs_volume_o_ro" {
  description = "Read-only NFS volume mount options (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

