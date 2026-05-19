variable "casc_config_path" {
  description = "Path to the Jenkins Configuration as Code YAML file shared through the tfvars/configuration mount."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/swarm/jenkins-controller/jenkins.yaml"
}

variable "casc_config_container_path" {
  description = "In-container path used by JCasC to read the shared Jenkins Configuration as Code YAML file."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/swarm/jenkins-controller/jenkins.yaml"
}

variable "mounts" {
  description = "Optional extra mount definitions appended after the default Jenkins mounts."
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
  description = "Environment variables applied to the Jenkins controller container; merged over the default shared agent secret path."
  type        = map(string)
  default     = {}
}

variable "agent_secrets_dir" {
  description = "Shared path where the controller writes Jenkins inbound agent secret files."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/swarm/jenkins-controller/agent-secrets"
}

variable "enable_shared_tfvars_mount" {
  description = "Whether to mount the shared tfvars/configuration root into the controller container."
  type        = bool
  default     = true
}

variable "shared_tfvars_volume_name" {
  description = "Docker volume name used for the shared tfvars/configuration mount."
  type        = string
  default     = "jenkins-controller-config"
}

variable "shared_tfvars_volume_driver" {
  description = "Docker volume driver used for the shared tfvars/configuration mount."
  type        = string
  default     = "local"
}

variable "shared_tfvars_volume_driver_opts" {
  description = <<-EOT
    Override NFS volume driver opts for the shared tfvars mount. When null, derived from
    terraform/providers/nfs.tfvars (swarm_nfs_volume_* and swarm_nfs_*_device).
  EOT
  type        = map(string)
  default     = null
  sensitive   = true
}

variable "shared_tfvars_mount_target" {
  description = "Container path where the shared tfvars/configuration root is mounted."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config"
}

variable "controller_image" {
  description = "Jenkins controller image reference"
  type        = string
  default     = "ghcr.io/nodadyoushutup/jenkins-controller:0.0.16"
}

variable "service_name" {
  description = "Docker Swarm service name for Jenkins controller"
  type        = string
  default     = "jenkins-controller"
}

variable "service_dns_alias" {
  description = "Service DNS alias on the overlay network"
  type        = string
  default     = "jenkins"
}

variable "network_name" {
  description = "Overlay network name for Jenkins services"
  type        = string
  default     = "jenkins"
}

variable "home_volume_name" {
  description = "Docker volume name used for Jenkins home persistence"
  type        = string
  default     = "jenkins-controller-home"
}

variable "home_mount_target" {
  description = "Container path for Jenkins home volume mount"
  type        = string
  default     = "/var/jenkins_home"
}

variable "controller_replicas" {
  description = "Number of Jenkins controller replicas"
  type        = number
  default     = 1
}

variable "controller_target_port" {
  description = "Controller HTTP port exposed by the container"
  type        = number
  default     = 8080
}

variable "controller_published_port" {
  description = "Published Swarm port for Jenkins HTTP UI/API"
  type        = number
  default     = 18082
}

variable "agent_target_port" {
  description = "Inbound agent TCP port exposed by the container"
  type        = number
  default     = 50000
}

variable "agent_published_port" {
  description = "Published Swarm port for inbound Jenkins agent traffic"
  type        = number
  default     = 50000
}

variable "placement_constraints" {
  description = "Swarm placement constraints for the controller service"
  type        = list(string)
  default     = ["node.labels.role==swarm-wk-1"]
}

variable "platform_architecture" {
  description = "CPU architecture used for service scheduling"
  type        = string
  default     = "aarch64"
}

variable "dns_nameservers" {
  description = <<-EOT
    DNS nameservers for Swarm task dns_config (and standalone runner dns). Set only in
    CONFIG_DIR/terraform/providers/dns.tfvars (merged by swarm_pipeline.sh before stack tfvars).
  EOT
  type        = list(string)
  sensitive   = true
}

variable "swarm_nfs_server" {
  description = <<-EOT
    Optional legacy; NFS mount options are swarm_nfs_volume_o_rw / swarm_nfs_volume_o_ro in nfs.tfvars.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "swarm_nfs_code_device" {
  description = <<-EOT
    NFS device/export for repo code (e.g. ":/mnt/eapp/code"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_config_device" {
  description = <<-EOT
    NFS device/export for shared config (e.g. ":/mnt/eapp/code/homelab/.config"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_type" {
  description = <<-EOT
    Docker local volume driver_opts.type for NFS-backed mounts (typically "nfs"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_o_rw" {
  description = <<-EOT
    Docker local volume driver_opts.o for read-write NFS (comma-separated options, e.g. addr=HOST,nfsvers=4.2,rw). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_o_ro" {
  description = <<-EOT
    Docker local volume driver_opts.o for read-only NFS (e.g. addr=HOST,nfsvers=4.2,ro). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/code/homelab/.config/terraform/providers/docker.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
  EOT
  type        = any
  default     = {}
}

# Vault KV fragments (parsed by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
variable "secrets" {
  type      = any
  default   = {}
  sensitive = true
}

variable "secret_files" {
  type      = any
  default   = {}
  sensitive = true
}
