variable "provider_config" {
  description = "Provider configuration map containing Jenkins credentials."
  type        = any
}

variable "job_definition_root" {
  description = "Repo-relative root scanned for Jenkins pipeline definitions."
  type        = string
  default     = "pipelines"
}

variable "job_definition_glob" {
  description = "Glob matched beneath job_definition_root to discover Jenkins pipeline definitions."
  type        = string
  default     = "**/*.jenkins"
}

variable "github_repo_url" {
  description = "Git URL Jenkins should use when loading pipeline definitions from SCM."
  type        = string
  default     = "https://github.com/nodadyoushutup/homelab.git"
}

variable "github_repo_branch" {
  description = "Legacy single-branch pipeline input retained for tfvars compatibility. Multibranch jobs ignore this value."
  type        = string
  default     = "main"
}

variable "branch_discovery_includes" {
  description = "Space-separated wildcard branch patterns Jenkins should include when indexing multibranch jobs."
  type        = string
  default     = "*"
}

variable "branch_discovery_excludes" {
  description = "Space-separated wildcard branch patterns Jenkins should exclude when indexing multibranch jobs."
  type        = string
  default     = ""
}

variable "prune_dead_branches" {
  description = "Whether Jenkins should prune deleted branches from multibranch jobs."
  type        = bool
  default     = true
}

variable "orphaned_item_days_to_keep" {
  description = "Days to keep orphaned multibranch child jobs. Use -1 to keep indefinitely."
  type        = number
  default     = -1
}

variable "orphaned_item_num_to_keep" {
  description = "Number of orphaned multibranch child jobs to keep. Use -1 to keep indefinitely."
  type        = number
  default     = 20
}

variable "github_credentials_id" {
  description = "Existing or Terraform-managed Jenkins credentials ID used for private GitHub checkout."
  type        = string
  default     = ""
}

variable "manage_github_credentials" {
  description = "Whether this Terraform stage should create the Jenkins GitHub username/password credential."
  type        = bool
  default     = false
}

variable "github_credentials_username" {
  description = "GitHub username associated with the Jenkins checkout credential."
  type        = string
  default     = ""
}

variable "github_credentials_password" {
  description = "GitHub password or personal access token associated with the Jenkins checkout credential."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_credentials_description" {
  description = "Description stored with the managed GitHub Jenkins credential."
  type        = string
  default     = "Managed by Terraform for private GitHub pipeline checkout"
}

variable "github_credentials_scope" {
  description = "Scope assigned to the managed GitHub Jenkins credential."
  type        = string
  default     = "GLOBAL"
}
