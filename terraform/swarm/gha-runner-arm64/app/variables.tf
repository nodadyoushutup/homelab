variable "access_token" {
  description = "Optional GitHub access token used to mint registration/remove tokens at runner startup (recommended for replicated runners)."
  type        = string
  sensitive   = true
  default     = ""
}


variable "engine_visible_build_path" {
  description = "Engine visible build path."
  type        = string
  default     = "/var/lib/gha-runner-engine-build"
}


variable "registration_token" {
  description = "GitHub Actions runner registration token from UI/API."
  type        = string
  sensitive   = true
  default     = "__SET_ME__"
}


variable "replicas" {
  description = "Number of Swarm service replicas."
  type        = number
  default     = 2
}


variable "url" {
  description = "GitHub repo or org URL for runner registration."
  type        = string
  default     = "__SET_ME__"
}


variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config."
  type        = list(string)
  sensitive   = true
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


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

