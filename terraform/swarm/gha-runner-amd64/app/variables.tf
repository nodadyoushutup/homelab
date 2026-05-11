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

variable "github_runner_name" {
  description = "Runner display name prefix in GitHub; Task slot and Task ID are appended."
  type        = string
  default     = "homelab-gha-runner-amd64"
}

variable "github_runner_replicas" {
  description = "Number of runner replicas to run in Swarm."
  type        = number
  default     = 2
}

variable "github_runner_labels" {
  description = "Comma-separated labels advertised by this runner pool."
  type        = string
  default     = "self-hosted,linux,homelab,amd64,build,kvm"
}

variable "github_runner_constraints" {
  description = "Swarm placement constraints for this runner pool."
  type        = list(string)
  default     = ["node.hostname==runner-amd64", "node.platform.arch==x86_64"]
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
