variable "provider_config" {
  description = "Configuration map passed to the Docker provider"
  type        = any
}

variable "env" {
  description = "Environment variables passed to the docker-volume-backup container"
  type        = map(string)
  default     = {}
}

variable "backup_mounts" {
  description = "Map of backup mounts where each object defines source volume and target path"
  type = map(object({
    source    = string
    target    = string
    type      = optional(string, "volume")
    read_only = optional(bool, true)
  }))
  default = {}
}
