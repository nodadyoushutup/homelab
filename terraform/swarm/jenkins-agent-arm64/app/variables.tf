variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "casc_config_path" {
  description = "Path to the Jenkins Configuration as Code YAML file used to derive agent node definitions."
  type        = string
  default     = "/mnt/eapp/config/jenkins-controller/jenkins.yaml"
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
  description = "Jenkins agent image reference."
  type        = string
  default     = "harbor.nodadyoushutup.com/jenkins-agent/jenkins-agent:latest"
}

variable "service_name_prefix" {
  description = "Docker Swarm service name prefix for Jenkins agents."
  type        = string
  default     = "jenkins-agent-arm64"
}

variable "network_name" {
  description = "Overlay network name shared with the Jenkins controller."
  type        = string
  default     = "jenkins"
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
  default     = "/mnt/eapp/config/jenkins-controller/agent-secrets"
}

variable "enable_shared_tfvars_mount" {
  description = "Whether to mount the shared tfvars/configuration root into each agent container."
  type        = bool
  default     = true
}

variable "shared_tfvars_volume_name" {
  description = "Docker volume name used for the shared tfvars/configuration bind mount."
  type        = string
  default     = "jenkins-agent-arm64-config"
}

variable "shared_tfvars_host_path" {
  description = "Host path for the shared tfvars/configuration root bind mount."
  type        = string
  default     = "/mnt/eapp/config"
}

variable "shared_tfvars_mount_target" {
  description = "Container path where the shared tfvars/configuration root is mounted."
  type        = string
  default     = "/mnt/eapp/config"
}

variable "placement_constraints" {
  description = "Swarm placement constraints applied to matching Jenkins agent services in addition to any hostname derived from JCasC."
  type        = list(string)
  default     = ["node.platform.arch==aarch64"]
}

variable "dns_nameservers" {
  description = "DNS resolver list configured inside Jenkins agent containers."
  type        = list(string)
  default = [
    "192.168.1.1",
    "1.1.1.1",
    "8.8.8.8",
  ]
}
