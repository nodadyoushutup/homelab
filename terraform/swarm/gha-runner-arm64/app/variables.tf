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


variable "nfs" {
  description = "Shared Swarm NFS homelab repo export and volume driver_opts (providers/nfs.tfvars)."
  type = object({
    device = string
    volume = object({
      type = string
      opts = string
    })
  })
  sensitive = true
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

