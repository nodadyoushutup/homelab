variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "image_reference" {
  description = "Official ChromaDB image to run."
  type        = string
  default     = "chromadb/chroma:latest@sha256:bd21353aee6ccdf4a57bd91e6001626826700f3838e1f230d4aae75bfd4889a1"
}

variable "published_port" {
  description = "Swarm ingress port exposed for the ChromaDB HTTP API."
  type        = number
  default     = 8000
}

variable "endpoint_host" {
  description = "Host used when reporting the external ChromaDB URL."
  type        = string
  default     = "192.168.1.120"
}

variable "replicas" {
  description = "Number of ChromaDB replicas to run. Keep at one for the local persistent volume."
  type        = number
  default     = 1
}

variable "placement_constraints" {
  description = "Swarm placement constraints for the ChromaDB service."
  type        = list(string)
  default     = ["node.labels.role==swarm-cp-0"]
}

variable "platform_architecture" {
  description = "Docker platform architecture for placement."
  type        = string
  default     = "aarch64"
}

variable "data_volume_name" {
  description = "Docker volume name used for ChromaDB persistent data."
  type        = string
  default     = "chromadb-data"
}

variable "dns_nameservers" {
  description = "DNS nameservers used by the ChromaDB task."
  type        = list(string)
  default = [
    "192.168.1.1",
    "1.1.1.1",
    "8.8.8.8",
  ]
}
