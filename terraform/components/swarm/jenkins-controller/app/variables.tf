# variables.tf
# External input contract for the Jenkins controller Swarm app slice.

variable "agent_published_port" {
  description = "Published Swarm port for inbound Jenkins agent traffic."
  type        = number
  default     = 50000
}


variable "agent_secrets_dir" {
  description = "Shared path where the controller writes Jenkins inbound agent secret files."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/components/swarm/jenkins-controller/agent-secrets"
}


variable "agent_target_port" {
  description = "Inbound agent TCP port exposed by the container."
  type        = number
  default     = 50000
}


variable "casc_config_container_path" {
  description = "In-container path used by JCasC to read the shared Jenkins Configuration as Code YAML file."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/components/swarm/jenkins-controller/jenkins.yaml"
}


variable "casc_config_path" {
  description = "Path to the Jenkins Configuration as Code YAML file shared through the tfvars/configuration mount."
  type        = string
  default     = "/mnt/eapp/code/homelab/.config/terraform/components/swarm/jenkins-controller/jenkins.yaml"
}
variable "controller_published_port" {
  description = "Published Swarm port for Jenkins HTTP UI/API."
  type        = number
  default     = 18082
}


variable "controller_replicas" {
  description = "Number of Jenkins controller replicas."
  type        = number
  default     = 1
}


variable "controller_target_port" {
  description = "Controller HTTP port exposed by the container."
  type        = number
  default     = 8080
}


variable "enable_shared_repo_mount" {
  description = "Whether to mount the homelab repo NFS export (nfs.device from nfs.tfvars) into the controller container."
  type        = bool
  default     = true
}


variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = {}
}


variable "home_mount_target" {
  description = "Container path for Jenkins home volume mount."
  type        = string
  default     = "/var/jenkins_home"
}


variable "home_volume_name" {
  description = "Docker volume name used for Jenkins home persistence."
  type        = string
  default     = "jenkins-controller-home"
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


variable "network_name" {
  description = "Overlay network name for Jenkins services."
  type        = string
  default     = "jenkins"
}


variable "service_dns_alias" {
  description = "Service DNS alias on the overlay network."
  type        = string
  default     = "jenkins"
}


variable "service_name" {
  description = "Docker Swarm service name for Jenkins controller."
  type        = string
  default     = "jenkins-controller"
}


variable "shared_repo_mount_target" {
  description = "Container path where the homelab repo NFS export is mounted."
  type        = string
  default     = "/mnt/eapp/code/homelab"
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


variable "shared_tfvars_volume_name" {
  description = "Docker volume name used for the shared tfvars/configuration mount."
  type        = string
  default     = "jenkins-controller-config"
}


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


variable "nfs" {
  description = "Shared Swarm NFS homelab repo export and volume driver_opts (components/swarm/nfs.tfvars)."
  type = object({
    device = string
    volume = object({
      type = string
      opts = string
    })
  })
  sensitive = true
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

