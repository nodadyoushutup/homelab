variable "provider_config" {
  description = <<-EOT
    Docker remote (host + ssh_opts). Optional nested registry_auth { address?, username, password }
    feeds both the docker provider and the Swarm service image pull — same pattern as gha-runner-arm64 / chromadb.
  EOT
  type        = any
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
  description = "Embedding provider used for ingest and query: google or openai."
  type        = string
  default     = "google"

  validation {
    condition     = contains(["google", "openai"], lower(var.embedding_provider))
    error_message = "embedding_provider must be google or openai."
  }
}

variable "openai_embedding_dimensions" {
  description = "Optional dimensions override for OpenAI text-embedding-3 models. Empty uses the model default."
  type        = string
  default     = ""
}

variable "workspace_host_path" {
  description = "Host path mounted read-only for repository ingest."
  type        = string
  default     = "/mnt/eapp/code/homelab"
}

variable "workspace_mount" {
  description = "Container path for the repository ingest mount."
  type        = string
  default     = "/workspace"
}
