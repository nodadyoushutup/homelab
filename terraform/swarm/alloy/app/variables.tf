variable "provider_config" {
  description = "Configuration for the Docker provider"
  type        = any
}

variable "alloy_config_path" {
  description = "Absolute path to alloy config stored outside the repo"
  type        = string
}
