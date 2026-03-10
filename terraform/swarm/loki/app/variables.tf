variable "provider_config" {
  description = "Configuration for the Docker provider"
  type        = any
}

variable "loki_config_path" {
  description = "Absolute path to loki config stored outside the repo"
  type        = string
}

variable "published_port" {
  description = "Ingress port exposed for Loki HTTP API"
  type        = number
  default     = 3100
}
