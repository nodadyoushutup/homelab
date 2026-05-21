variable "env" {
  description = "Container environment variables."
  type        = map(string)
  default     = {}
  sensitive   = true
}


variable "env_file_path" {
  description = "Optional dotenv file path for container secrets and settings."
  type        = string
  default     = ""
}


variable "image_reference" {
  description = "Container image reference to deploy."
  type        = string
  default     = "homelab/mcp-terraform:2026.04.16.1"
}


variable "published_port" {
  description = "Swarm ingress published port."
  type        = number
  default     = 18104
}


variable "replicas" {
  description = "Number of Swarm service replicas."
  type        = number
  default     = 1
}


variable "terraform_toolsets" {
  description = "Terraform MCP toolsets used when MCP_TERRAFORM_TOOLSETS is not supplied through env."
  type        = string
  default     = "registry"
}


variable "timezone" {
  description = "Container TZ environment value."
  type        = string
  default     = "America/New_York"
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


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

