variable "allowed_hosts" {
  description = "Host headers accepted by the HTTP MCP server. Use [\"*\"] for internal-only wildcard access."
  type        = list(string)
  default     = ["*"]
}


variable "config_file" {
  description = "Playwright MCP config JSON path inside the task (must be on the NFS code mount)."
  type        = string
  default     = "/mnt/eapp/code/homelab/terraform/swarm/mcp-playwright/app/config.json"
}


variable "endpoint_host" {
  description = "Host name used for external URL reporting."
  type        = string
  default     = "192.168.1.120"
}


variable "image_reference" {
  description = "Container image reference to deploy."
  type        = string
  default     = "mcr.microsoft.com/playwright/mcp:latest"
}


variable "output_dir" {
  description = "Container path where Playwright MCP writes snapshots, logs, and other non-screenshot output files."
  type        = string
  default     = "/mnt/eapp/code/homelab/data/playwright"
}


variable "published_port" {
  description = "Swarm ingress published port."
  type        = number
  default     = 8931
}


variable "replicas" {
  description = "Number of Swarm service replicas."
  type        = number
  default     = 1
}


variable "screenshot_dir" {
  description = "Container path used as the working directory so relative screenshot filenames are written here."
  type        = string
  default     = "/mnt/eapp/code/homelab/data/screenshots"
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

