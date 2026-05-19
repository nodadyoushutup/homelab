variable "image_reference" {
  description = "Official prometheus-pve-exporter image."
  type        = string
  default     = "prompve/prometheus-pve-exporter@sha256:4527b8080c4bd53ae8d7326ff7a3469dad0c1abb5753ff0bae9f1ef1c23cb2c9"
}

variable "published_port" {
  description = "Host-published TCP port for Prometheus scrapes (publish_mode host on endpoint_host node)."
  type        = number
  default     = 9221
}

variable "endpoint_host" {
  description = "Swarm node IP where the exporter task is published (typically swarm-wk-0)."
  type        = string
  default     = "192.168.1.121"
}

variable "pve_targets" {
  description = "Proxmox VE API hostnames or IPs scraped via /pve?target= (one cluster job per target)."
  type        = list(string)
  default     = ["192.168.1.10"]
}

variable "placement_constraints" {
  description = "Swarm placement constraints for the exporter service."
  type        = list(string)
  default     = ["node.labels.role==swarm-wk-0"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "verify_ssl" {
  description = "When false, sets PVE_VERIFY_SSL=false for self-signed PVE API certificates."
  type        = bool
  default     = false
}

variable "disable_config_collector" {
  description = "Disable per-guest config collector (extra API calls per VM/CT)."
  type        = bool
  default     = true
}

variable "env" {
  description = "Exporter auth env (PVE_USER, PVE_TOKEN_NAME, PVE_TOKEN_VALUE). See ensure_pve_prometheus_api_token.sh."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "dns_nameservers" {
  description = <<-EOT
    DNS nameservers for Swarm task dns_config. Set in CONFIG_DIR/terraform/providers/dns.tfvars.
  EOT
  type        = list(string)
  sensitive   = true
}

variable "swarm_nfs_server" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_code_device" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_config_device" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_volume_type" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_volume_o_rw" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_nfs_volume_o_ro" {
  type      = string
  sensitive = true
  default   = ""
}

variable "swarm_docker_provider_config" {
  description = "Shared Docker SSH host and registry credentials."
  type        = any
  default     = {}
}

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
