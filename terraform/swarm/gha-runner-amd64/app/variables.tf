variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any

  default = {}
}

variable "github_runner_url" {
  description = "GitHub repo or org URL for runner registration."
  type        = string
  default     = "__SET_ME__"
}

variable "github_runner_token" {
  description = "GitHub Actions runner registration token from UI/API."
  type        = string
  sensitive   = true
  default     = "__SET_ME__"
}

variable "github_runner_access_token" {
  description = "Optional GitHub access token used to mint registration/remove tokens at runner startup (recommended for replicated runners)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_runner_image" {
  description = "Container image reference for the runner service (prefer published multi-arch tags)."
  type        = string
  default     = "ghcr.io/nodadyoushutup/gha-runner:0.0.5"
}

variable "github_runner_name" {
  description = "Runner display name prefix in GitHub; Task slot and Task ID are appended."
  type        = string
  default     = "homelab-gha-runner-amd64"
}

variable "github_runner_replicas" {
  description = "Number of runner containers on the pool host (see provider_config.docker in tfvars)."
  type        = number
  default     = 2
}

variable "github_runner_labels" {
  description = "Comma-separated labels advertised by this runner pool."
  type        = string
  default     = "self-hosted,linux,homelab,amd64,build,kvm"
}

variable "github_runner_workdir" {
  description = "Working directory inside the runner install."
  type        = string
  default     = "_work"
}

variable "github_runner_engine_visible_build_path" {
  description = <<-EOT
    Absolute path bind-mounted from the pool host into each runner container at the identical path.
    The container sets HARBOR_BUILD_TMP_PARENT to this value so Harbor clones (and any
    Makefile nested `docker run -v $PWD:$PWD`) live on the host filesystem visible to the
    Docker engine when the task only mounts /var/run/docker.sock.
    The directory must already exist on the pool host before apply.
    The entrypoint runs `mkdir -p` under that mount for job subdirs once the bind succeeds.
  EOT
  type        = string
  default     = "/var/lib/gha-runner-engine-build"
}

variable "github_runner_ephemeral" {
  description = "Whether the runner should be ephemeral (single-job)."
  type        = bool
  default     = true
}

variable "github_runner_disableupdate" {
  description = "Disable runner self-updates."
  type        = bool
  default     = true
}

variable "github_runner_remove_token" {
  description = "Optional token to deregister runner on container shutdown."
  type        = string
  sensitive   = true
  default     = ""
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/config/providers/docker.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
    Merged with provider_config; per-stack tfvars override on key collision.
    For runner pools, override `docker` in provider_config so Terraform targets the pool host
    (standalone `docker_container`, not Swarm scheduling).
  EOT
  type        = any
  default     = {}
}

locals {
  provider_config = merge(var.swarm_docker_provider_config, var.provider_config)
  docker_registry_auths = (
    try(local.provider_config.registry_auths, null) != null
    ? local.provider_config.registry_auths
    : (
      try(local.provider_config.registry_auth, null) != null
      ? [local.provider_config.registry_auth]
      : []
    )
  )
  # docker_container uses provider-level registry_auth; pick the entry for this image's registry.
  github_runner_registry_host = split("/", var.github_runner_image)[0]
  runner_registry_matching_auths = [
    for a in local.docker_registry_auths : a
    if coalesce(try(a.address, null), "ghcr.io") == local.github_runner_registry_host
  ]
  docker_registry_auth_for_runner_image = (
    length(local.runner_registry_matching_auths) > 0 ? local.runner_registry_matching_auths[0] : null
  )
}

