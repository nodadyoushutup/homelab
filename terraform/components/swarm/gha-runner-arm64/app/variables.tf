# variables.tf
# External input contract for the GHA runner (ARM64) Docker app slice.

variable "env" {
  description = "Container environment variables (components/swarm/nfs.tfvars and slice tfvars). GH_RUNNER_NAME is set per replica in main.tf."
  type        = map(string)
  sensitive   = true
}
variable "replicas" {
  description = "Number of runner containers on the pool host."
  type        = number
  default     = 4
}


variable "dns_nameservers" {
  description = "DNS nameservers for container DNS."
  type        = list(string)
  sensitive   = true
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
  description = "Which nfs_shares entry this slice mounts (catalog key)."
  type        = string
  default     = "code"
}


variable "nfs_subpath" {
  description = "Path under the selected share's export to mount (e.g. /homelab). Empty mounts the export root."
  type        = string
  default     = ""
}


variable "nfs_mount_target" {
  description = "Container path where the selected NFS export is mounted."
  type        = string
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
