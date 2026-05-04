variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
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
  default     = "ghcr.io/nodadyoushutup/gha-runner:0.0.1"
}

variable "github_runner_name" {
  description = "Runner display name prefix in GitHub; Task slot and Task ID are appended."
  type        = string
  default     = "homelab-gha-runner-arm64"
}

variable "github_runner_replicas" {
  description = "Number of runner replicas to run in Swarm."
  type        = number
  default     = 4
}

variable "github_runner_labels" {
  description = "Comma-separated labels advertised by this runner pool."
  type        = string
  default     = "self-hosted,linux,homelab,arm64"
}

variable "github_runner_constraints" {
  description = "Swarm placement constraints for this runner pool."
  type        = list(string)
  default     = ["node.role==worker", "node.platform.arch==aarch64"]
}

variable "github_runner_workdir" {
  description = "Working directory inside the runner install."
  type        = string
  default     = "_work"
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

variable "enable_shared_tfvars_mount" {
  description = "Whether to mount the shared tfvars/configuration root into the runner container."
  type        = bool
  default     = true
}

variable "shared_tfvars_volume_name" {
  description = "Docker volume name used for the shared tfvars/configuration mount."
  type        = string
  default     = "gha-runner-arm64-config"
}

variable "shared_tfvars_volume_driver" {
  description = "Docker volume driver used for the shared tfvars/configuration mount."
  type        = string
  default     = "local"
}

variable "shared_tfvars_volume_driver_opts" {
  description = "Docker volume driver options for the shared tfvars/configuration mount. Defaults to mounting the shared NFS export directly."
  type        = map(string)
  default = {
    type   = "nfs"
    o      = "addr=192.168.1.100,nfsvers=4.2,rw"
    device = ":/mnt/eapp/config"
  }
}

variable "shared_tfvars_mount_target" {
  description = "Container path where the shared tfvars/configuration root is mounted."
  type        = string
  default     = "/mnt/eapp/config"
}
