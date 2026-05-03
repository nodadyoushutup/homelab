variable "provider_config" {
  description = "Configuration for the Docker provider"
  type        = any
}

variable "casc_config_path" {
  description = "Path to the Jenkins Configuration as Code YAML file shared through the tfvars/configuration mount."
  type        = string
  default     = "/mnt/eapp/config/jenkins-controller/jenkins.yaml"
}

variable "casc_config_container_path" {
  description = "In-container path used by JCasC to read the shared Jenkins Configuration as Code YAML file."
  type        = string
  default     = "/mnt/eapp/config/jenkins-controller/jenkins.yaml"
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
  default     = "/mnt/eapp/config/jenkins-controller/agent-secrets"
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
  description = "Docker volume driver options for the shared tfvars/configuration mount. Defaults to mounting the shared NFS export directly."
  type        = map(string)
  default = {
    type   = "nfs"
    o      = "addr=192.168.1.100,nfsvers=4.2,rw"
    device = ":/mnt/eapp/config"
  }
}

variable "shared_tfvars_mount_target" {
  description = "Container path where the shared tfvars/configuration root is mounted."
  type        = string
  default     = "/mnt/eapp/config"
}

variable "controller_image" {
  description = "Jenkins controller image reference"
  type        = string
  default     = "harbor.nodadyoushutup.com/jenkins-controller/jenkins-controller:0.0.3"
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
  default     = ["node.labels.role==swarm-cp-0"]
}

variable "platform_architecture" {
  description = "CPU architecture used for service scheduling"
  type        = string
  default     = "aarch64"
}

variable "dns_nameservers" {
  description = "DNS resolver list configured inside the Jenkins controller container"
  type        = list(string)
  default = [
    "192.168.1.1",
    "1.1.1.1",
    "8.8.8.8",
  ]
}
