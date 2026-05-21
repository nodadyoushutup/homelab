variable "chroma_collection" {
  description = "Chroma collection used for repository RAG chunks."
  type        = string
  default     = "homelab"
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


variable "chromadb_network_name" {
  description = "Existing ChromaDB overlay network name."
  type        = string
  default     = "chromadb"
}


variable "embedding_model" {
  description = "Embedding model id used for ingest and query. Empty uses the provider default."
  type        = string
  default     = ""
}


variable "embedding_provider" {
  description = "Embedding provider used for ingest and query: openai (default), google, or anthropic (Voyage via VOYAGE_API_KEY)."
  type        = string
  default     = "openai"

  validation {
    condition     = contains(["google", "openai", "anthropic"], lower(var.embedding_provider))
    error_message = "embedding_provider must be google, openai, or anthropic."
  }
}


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
  default     = "harbor.nodadyoushutup.com/homelab/rag-engine:0.0.7"
}


variable "openai_embedding_dimensions" {
  description = "Optional dimensions override for OpenAI text-embedding-3 models. Empty uses the model default."
  type        = string
  default     = ""
}


variable "published_port" {
  description = "Swarm ingress published port."
  type        = number
  default     = 9015
}


variable "rag_engine_network_name" {
  description = "Overlay network name shared by RAG engine clients."
  type        = string
  default     = "rag-engine"
}


variable "replicas" {
  description = "Number of Swarm service replicas."
  type        = number
  default     = 1
}


variable "timezone" {
  description = "Container TZ environment value."
  type        = string
  default     = "America/New_York"
}


variable "workspace_mount" {
  description = "Container path for repository ingest (path under the NFS code mount)."
  type        = string
  default     = "/mnt/eapp/code/homelab"
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


variable "swarm_nfs_volume_o_ro" {
  description = "Read-only NFS volume mount options (from nfs.tfvars)."
  type        = string
  sensitive   = true
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

