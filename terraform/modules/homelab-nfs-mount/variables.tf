variable "volume_name" {
  description = "Swarm-local Docker volume name (unique per service mount)."
  type        = string
}

variable "target" {
  description = "Absolute mount path inside the container."
  type        = string
}

variable "device" {
  description = "NFS export device path (e.g. :/mnt/eapp/code) as used by the local volume NFS driver."
  type        = string
}

variable "nfs_server" {
  description = "NFS server address or hostname."
  type        = string
  default     = "192.168.1.100"
}

variable "mount_options" {
  description = "Comma-separated NFS mount options excluding addr= and rw/ro (rw/ro follows read_only)."
  type        = string
  default     = "nfsvers=4.2"
}

variable "read_only" {
  description = "When true, pass ro in mount options and set the Swarm mount read_only flag."
  type        = bool
  default     = false
}
