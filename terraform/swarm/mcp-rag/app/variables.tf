variable "image_reference" {
  description = "RAG MCP image to run."
  type        = string
  default     = "harbor.nodadyoushutup.com/homelab/mcp-rag:latest"
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
  default     = ["node.labels.role==swarm-wk-4"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
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
