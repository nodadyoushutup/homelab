variable "image_reference" {
  description = "RAG engine image to run."
  type        = string
  default     = "harbor.nodadyoushutup.com/homelab/rag-engine:0.0.7"
}

variable "placement" {
  description = "Swarm task placement (constraints and platforms). Omit in tfvars to skip placement in the task spec."
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
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



variable "dns_nameservers" {
  description = <<-EOT
    DNS nameservers for Swarm task dns_config (and standalone runner dns). Set only in
    CONFIG_DIR/terraform/providers/dns.tfvars (merged by swarm_pipeline.sh before stack tfvars).
  EOT
  type        = list(string)
  sensitive   = true
}

variable "swarm_nfs_server" {
  description = <<-EOT
    Optional legacy; NFS mount options are swarm_nfs_volume_o_rw / swarm_nfs_volume_o_ro in nfs.tfvars.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "swarm_nfs_code_device" {
  description = <<-EOT
    NFS device/export for repo code (e.g. ":/mnt/eapp/code"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_config_device" {
  description = <<-EOT
    NFS device/export for shared config (e.g. ":/mnt/eapp/code/homelab/.config"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_type" {
  description = <<-EOT
    Docker local volume driver_opts.type for NFS-backed mounts (typically "nfs"). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_o_rw" {
  description = <<-EOT
    Docker local volume driver_opts.o for read-write NFS (comma-separated options, e.g. addr=HOST,nfsvers=4.2,rw). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
}

variable "swarm_nfs_volume_o_ro" {
  description = <<-EOT
    Docker local volume driver_opts.o for read-only NFS (e.g. addr=HOST,nfsvers=4.2,ro). Set only in CONFIG_DIR/terraform/providers/nfs.tfvars.
  EOT
  type        = string
  sensitive   = true
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
  description = "Embedding provider used for ingest and query: openai (default), google, or anthropic (Voyage via VOYAGE_API_KEY)."
  type        = string
  default     = "openai"

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

variable "workspace_mount" {
  description = "Container path for repository ingest (path under the NFS code mount)."
  type        = string
  default     = "/mnt/eapp/code/homelab"
}

variable "swarm_docker_provider_config" {
  description = <<-EOT
    Shared Docker SSH host and registry credentials (GHCR, Harbor, etc.).
    Set in /mnt/eapp/code/homelab/.config/terraform/providers/docker_arm64.tfvars; Swarm app pipelines source
    scripts/terraform/swarm_docker_provider_tfvars_env.sh so terraform receives this file.
  EOT
  type        = any
  default     = {}
}

# Vault KV fragments (parsed by scripts/terraform/vault_merge_config_secrets.py); unused by this module.
variable "secrets" {
  type      = any
  default   = {}
  sensitive = true
}

variable "secret_files" {
  type      = any
  default   = {}
  sensitive = true
}
