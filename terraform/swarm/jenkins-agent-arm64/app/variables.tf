variable "casc_config_path" {
  description = "Path to the Jenkins Configuration as Code YAML file used to derive agent node definitions."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/swarm/jenkins-controller/jenkins.yaml"
}

variable "agent_label_filter" {
  description = "Required Jenkins label tokens used to select matching node definitions from JCasC."
  type        = list(string)
  default     = ["arm64"]
}

variable "mounts" {
  description = "Optional extra mount definitions appended after the default shared tfvars/configuration mount."
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
  description = "Environment variables applied to each Jenkins agent container; merged over the default shared agent secret path."
  type        = map(string)
  default     = {}
}

variable "agent_image" {
  description = "Jenkins agent image reference validated during stage preflight and applied to each pool container."
  type        = string
  default     = "ghcr.io/nodadyoushutup/jenkins-agent:0.0.9"
}

variable "engine_visible_build_path" {
  description = <<-EOT
    Absolute path bind-mounted from the pool host for nested Docker builds (Harbor/Packer job workspaces).
    Must exist on the pool host before apply.
  EOT
  type        = string
  default     = "/var/lib/gha-runner-engine-build"
}

variable "kvm_supplementary_groups" {
  description = "Supplementary groups for /dev/kvm; include the pool host KVM gid (device node keeps host ownership)."
  type        = list(string)
  default     = ["kvm", "992"]
}

variable "service_name_prefix" {
  description = "Prefix for Docker volume names on the pool host."
  type        = string
  default     = "jenkins-agent-arm64"
}

variable "jenkins_url" {
  description = "Jenkins controller URL used by inbound agents."
  type        = string
  default     = "http://jenkins:8080"
}

variable "default_remote_fs" {
  description = "Fallback remote filesystem path when a JCasC node does not define remoteFS."
  type        = string
  default     = "/home/jenkins"
}

variable "home_volume_name_prefix" {
  description = "Docker volume name prefix used for Jenkins agent home persistence."
  type        = string
  default     = "jenkins-agent-arm64-home"
}

variable "agent_secrets_dir" {
  description = "Shared path where the controller writes Jenkins inbound agent secret files for agents to read."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/swarm/jenkins-controller/agent-secrets"
}

variable "enable_shared_tfvars_mount" {
  description = "Whether to mount the shared tfvars/configuration root into each agent container."
  type        = bool
  default     = true
}

variable "enable_shared_code_mount" {
  description = "Whether to mount the shared code NFS export (swarm_nfs_code_device from nfs.tfvars) into each agent container."
  type        = bool
  default     = true
}

variable "shared_tfvars_volume_name" {
  description = "Docker volume name used for the shared tfvars/configuration mount."
  type        = string
  default     = "jenkins-agent-arm64-config"
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

variable "placement_constraints" {
  description = "Deprecated (Swarm-only). Retained for tfvars compatibility; pool-host containers ignore this."
  type        = list(string)
  default     = []
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
