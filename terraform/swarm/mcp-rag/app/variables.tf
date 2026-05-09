variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "registry_auth" {
  description = "Optional registry auth for pulling the service image."
  type        = any
  default     = null
  sensitive   = true
}

variable "image_reference" {
  description = "RAG MCP image to run."
  type        = string
  default     = "harbor.nodadyoushutup.com/mcp-rag/mcp-rag:latest"
}

variable "env_file_path" {
  description = "Optional dotenv file containing MCP RAG secrets and settings."
  type        = string
  default     = ""
}

variable "env" {
  description = "Additional environment variables to pass to the container."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "published_port" {
  description = "Swarm ingress port exposed for the RAG MCP HTTP endpoint."
  type        = number
  default     = 9016
}

variable "endpoint_host" {
  description = "Host used when reporting the external MCP URL."
  type        = string
  default     = "192.168.1.120"
}

variable "timezone" {
  description = "Container timezone."
  type        = string
  default     = "America/New_York"
}

variable "replicas" {
  description = "Number of RAG MCP replicas to run."
  type        = number
  default     = 1
}

variable "placement_constraints" {
  description = "Swarm placement constraints for this service."
  type        = list(string)
  default     = ["node.labels.role==swarm-cp-0"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "dns_nameservers" {
  description = "DNS nameservers used by the task."
  type        = list(string)
  default = [
    "192.168.1.1",
    "1.1.1.1",
    "8.8.8.8",
  ]
}

variable "rag_engine_network_name" {
  description = "Existing RAG engine overlay network name."
  type        = string
  default     = "rag-engine"
}

variable "rag_engine_base_url" {
  description = "Base URL used by mcp-rag to call the RAG engine."
  type        = string
  default     = "http://rag-engine:8080"
}

variable "request_timeout_seconds" {
  description = "Timeout for mcp-rag calls to the RAG engine."
  type        = number
  default     = 120
}

variable "log_level" {
  description = "Uvicorn / application log level."
  type        = string
  default     = "INFO"
}
