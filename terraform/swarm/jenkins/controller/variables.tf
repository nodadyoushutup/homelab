variable "provider_config" {
  description = "Configuration for the Docker provider"
  type        = any
}

variable "casc_config" {
  description = "Jenkins Configuration as Code object that is rendered to /var/jenkins_home/jenkins.yaml"
  type        = any
  default = {
    jenkins = {
      nodes = []
    }
  }
}

variable "mounts" {
  description = "Optional extra mount definitions appended to the baked Jenkins mounts"
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
  description = "Environment variables applied to the Jenkins controller container"
  type        = map(string)
  default = {
    SECRETS_DIR = "/var/jenkins_home/.jenkins"
  }
}

variable "controller_image" {
  description = "Jenkins controller image reference"
  type        = string
  default     = "ghcr.io/nodadyoushutup/jenkins-controller:0.0.1"
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
  default     = 18080
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
