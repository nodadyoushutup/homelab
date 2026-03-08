variable "provider_config" {
  description = "Provider configuration map (docker and Jenkins credentials)."
  type        = any
}

variable "casc_config" {
  description = "Jenkins Configuration as Code structure; provides node definitions."
  type        = any
}

variable "mounts" {
  description = "Optional extra mount definitions appended to the baked Jenkins mounts."
  type = list(object({
    name        = string
    target      = string
    driver      = string
    driver_opts = map(string)
    no_copy     = bool
  }))
  default = []
}

variable "env" {
  description = "Environment variables applied to Jenkins agents."
  type        = map(string)
  default     = {}
}

variable "controller_service_id" {
  description = "Swarm service ID for the Jenkins controller."
  type        = string
}

variable "controller_image" {
  description = "Container image digest used by the Jenkins controller."
  type        = string
}
