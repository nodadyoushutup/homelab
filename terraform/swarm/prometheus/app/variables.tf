variable "provider_config" {
  description = "Configuration map passed to the Docker provider"
  type        = any
}

variable "prometheus_config_path" {
  description = "Absolute path to prometheus.yaml stored outside the repo"
  type        = string
}
