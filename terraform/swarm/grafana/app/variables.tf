variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)"
  type        = any
}

variable "env" {
  description = "Environment variables to pass to the Grafana container"
  type        = map(string)
  default     = null
}

variable "grafana_ini_path" {
  description = "Absolute path to grafana.ini stored outside the repo"
  type        = string
}
