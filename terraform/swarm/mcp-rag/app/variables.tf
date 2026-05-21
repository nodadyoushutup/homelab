variable "endpoint_host" {
  description = "Host name used for external URL reporting."
  type        = string
  default     = "192.168.1.120"
}


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
  default     = "harbor.nodadyoushutup.com/homelab/mcp-rag:latest"
}


variable "log_level" {
  description = "Uvicorn / application log level."
  type        = string
  default     = "INFO"
}


variable "published_port" {
  description = "Swarm ingress published port."
  type        = number
  default     = 9016
}


variable "rag_engine_base_url" {
  description = "Base URL used by mcp-rag to call the RAG engine."
  type        = string
  default     = "http://rag-engine:8080"
}


variable "rag_engine_network_name" {
  description = "Existing RAG engine overlay network name."
  type        = string
  default     = "rag-engine"
}


variable "replicas" {
  description = "Number of Swarm service replicas."
  type        = number
  default     = 1
}


variable "request_timeout_seconds" {
  description = "Timeout for mcp-rag calls to the RAG engine."
  type        = number
  default     = 120
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

