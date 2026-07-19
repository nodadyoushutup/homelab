# variables.tf
# External input contract for the cloud-image-repository Swarm app slice.

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

variable "docker_providers" {
  description = "Shared Docker provider catalog (map keyed by machine name); config-id terraform/providers/docker."
  type        = any
}

variable "registry_auths" {
  description = "Shared container registry auths reused by every Swarm slice."
  type        = any
  default     = []
}

variable "docker_machine" {
  description = "Which docker_providers entry this slice connects through."
  type        = string
}

variable "nfs_shares" {
  description = "Catalog of existing NFS exports (config-id terraform/nfs), keyed by name."
  type = map(object({
    server      = string
    export      = string
    mount_point = string
    options     = string
  }))
  sensitive = true
}


variable "nfs_share" {
  description = "Which nfs_shares entry backs the served /data directory (catalog key)."
  type        = string
  default     = "code"
}


variable "nfs_subpath" {
  description = "Path under the selected share's export to mount (e.g. /homelab/.../data/packer). Empty mounts the export root."
  type        = string
  default     = ""
}
