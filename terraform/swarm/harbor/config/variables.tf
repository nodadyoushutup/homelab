variable "delete_default_library" {
  description = "Delete default library."
  type        = bool
  default     = true
}


variable "manage_system_config" {
  description = "When true, apply the harbor_config_system resource using system_config values."
  type        = bool
  default     = false
}


variable "project_members" {
  description = "Optional user memberships for managed projects. project_name must reference an entry in projects."
  type = list(object({
    project_name = string
    user_name    = string
    role         = string
  }))
  default = []
}


variable "projects" {
  description = "Projects."
  type = list(object({
    name                        = string
    public                      = optional(bool)
    vulnerability_scanning      = optional(bool)
    auto_sbom_generation        = optional(bool)
    enable_content_trust        = optional(bool)
    enable_content_trust_cosign = optional(bool)
    deployment_security         = optional(string)
    cve_allowlist               = optional(list(string))
    proxy_speed_kb              = optional(number)
    storage_quota               = optional(number)
    force_destroy               = optional(bool)
  }))
  default = []
}


variable "provider_config" {
  description = "Provider API URL and credentials for this config slice."
  type = object({
    harbor = object({
      url          = string
      username     = string
      password     = optional(string)
      bearer_token = optional(string)
      session_id   = optional(string)
      insecure     = optional(bool)
      api_version  = optional(number)
      robot_prefix = optional(string)
    })
  })
}


variable "robot_accounts" {
  description = "Optional robot account specs. Each item should match provider schema for harbor_robot_account."
  type        = list(any)
  default     = []
}


variable "system_config" {
  description = "Optional system-wide Harbor configuration map (used only when manage_system_config is true)."
  type        = any
  default     = {}
}


variable "users" {
  description = "Optional local Harbor users to create/manage."
  type = list(object({
    username  = string
    email     = string
    full_name = string
    password  = string
    admin     = optional(bool)
    comment   = optional(string)
  }))
  default = []
}

