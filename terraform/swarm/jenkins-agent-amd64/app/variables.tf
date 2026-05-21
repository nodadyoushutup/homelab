variable "agent_image" {
  description = "Jenkins agent image reference validated during stage preflight and applied to each pool container."
  type        = string
  default     = "ghcr.io/nodadyoushutup/jenkins-agent:0.0.9"
}


variable "agent_label_filter" {
  description = "Required Jenkins label tokens used to select matching node definitions from JCasC."
  type        = list(string)
  default     = ["amd64"]
}


variable "agent_secrets_dir" {
  description = "Shared path where the controller writes Jenkins inbound agent secret files for agents to read."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/swarm/jenkins-controller/agent-secrets"
}


variable "casc_config_path" {
  description = "Path to the Jenkins Configuration as Code YAML file used to derive agent node definitions."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/swarm/jenkins-controller/jenkins.yaml"
}


variable "default_remote_fs" {
  description = "Fallback remote filesystem path when a JCasC node does not define remoteFS."
  type        = string
  default     = "/home/jenkins"
}


variable "enable_shared_code_mount" {
  description = "Whether to mount the shared code NFS export (swarm_nfs_code_device from nfs.tfvars) into each agent container."
  type        = bool
  default     = true
}


variable "enable_shared_tfvars_mount" {
  description = "Whether to mount the shared tfvars/configuration root into each agent container."
  type        = bool
  default     = true
}


variable "engine_visible_build_path" {
  description = "Engine visible build path."
  type        = string
  default     = "/var/lib/gha-runner-engine-build"
}


variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = {}
}


variable "home_volume_name_prefix" {
  description = "Docker volume name prefix used for Jenkins agent home persistence."
  type        = string
  default     = "jenkins-agent-amd64-home"
}


variable "jenkins_url" {
  description = "Jenkins controller URL used by inbound agents."
  type        = string
  default     = "http://jenkins:8080"
}


variable "kvm_supplementary_groups" {
  description = "Supplementary groups for /dev/kvm; include the pool host KVM gid (device node keeps host ownership)."
  type        = list(string)
  default     = ["kvm", "993"]
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


variable "service_name_prefix" {
  description = "Prefix for Docker volume names on the pool host."
  type        = string
  default     = "jenkins-agent-amd64"
}


variable "shared_tfvars_mount_target" {
  description = "Container path where the shared tfvars/configuration root is mounted."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config"
}


variable "shared_tfvars_volume_driver" {
  description = "Docker volume driver used for the shared tfvars/configuration mount."
  type        = string
  default     = "local"
}


variable "shared_tfvars_volume_driver_opts" {
  description = "Shared tfvars volume driver opts."
  type        = map(string)
  default     = null
  sensitive   = true
}


variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config."
  type        = list(string)
  sensitive   = true
}


variable "swarm_nfs_code_device" {
  description = "NFS export for homelab code (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_nfs_config_device" {
  description = "NFS export for homelab config (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_nfs_volume_type" {
  description = "Docker volume driver type for NFS mounts (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_nfs_volume_o_rw" {
  description = "Read-write NFS volume mount options (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

