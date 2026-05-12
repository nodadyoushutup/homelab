variable "provider_config" {
  description = <<-EOT
    Docker remote (host + ssh_opts). Optional nested registry_auth { address?, username, password }
    feeds both the docker provider and the Swarm service image pull — same pattern as gha-runner-arm64 / chromadb.
  EOT
  type        = any

  default = {}
}

variable "image_reference" {
  description = "RAG engine image to run."
  type        = string
  default     = "ghcr.io/nodadyoushutup/rag-engine:0.0.6"
}

variable "env_file_path" {
  description = "Optional dotenv file containing RAG engine secrets and settings."
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
  description = "Swarm ingress port exposed for the RAG engine HTTP API."
  type        = number
  default     = 9015
}

variable "endpoint_host" {
  description = "Host used when reporting the external RAG engine URL."
  type        = string
  default     = "192.168.1.120"
}

variable "timezone" {
  description = "Container timezone."
  type        = string
  default     = "America/New_York"
}

variable "replicas" {
  description = "Number of RAG engine replicas to run."
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
  description = "Overlay network name shared by RAG engine clients."
  type        = string
  default     = "rag-engine"
}

variable "chromadb_network_name" {
  description = "Existing ChromaDB overlay network name."
  type        = string
  default     = "chromadb"
}

variable "chroma_host" {
  description = "ChromaDB hostname visible from the RAG engine task."
  type        = string
  default     = "chromadb"
}

variable "chroma_port" {
  description = "ChromaDB HTTP port visible from the RAG engine task."
  type        = number
  default     = 8000
}

variable "chroma_collection" {
  description = "Chroma collection used for repository RAG chunks."
  type        = string
  default     = "homelab"
}

variable "embedding_model" {
  description = "Embedding model id used for ingest and query. Empty uses the provider default."
  type        = string
  default     = ""
}

variable "embedding_provider" {
  description = "Embedding provider used for ingest and query: google, openai, or anthropic (Voyage via VOYAGE_API_KEY)."
  type        = string
  default     = "google"

  validation {
    condition     = contains(["google", "openai", "anthropic"], lower(var.embedding_provider))
    error_message = "embedding_provider must be google, openai, or anthropic."
  }
}

variable "openai_embedding_dimensions" {
  description = "Optional dimensions override for OpenAI text-embedding-3 models. Empty uses the model default."
  type        = string
  default     = ""
}

variable "nfs_server" {
  description = "NFS server for the homelab code export."
  type        = string
  default     = "192.168.1.100"
}

variable "nfs_code_device" {
  description = "NFS export for repo code (mounted read-only at /mnt/eapp/code)."
  type        = string
  default     = ":/mnt/eapp/code"
}

variable "workspace_mount" {
  description = "Container path for repository ingest (path under the NFS code mount)."
  type        = string
  default     = "/mnt/eapp/code/homelab"
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/config/providers/docker.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
    Merged with provider_config; per-stack tfvars override on key collision.
  EOT
  type        = any
  default     = {}
}

locals {
  provider_config = merge(var.swarm_docker_provider_config, var.provider_config)
  docker_registry_auths = (
    try(local.provider_config.registry_auths, null) != null
    ? local.provider_config.registry_auths
    : (
      try(local.provider_config.registry_auth, null) != null
      ? [local.provider_config.registry_auth]
      : []
    )
  )
}

