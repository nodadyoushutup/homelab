variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)"
  type        = any
}

variable "env" {
  description = "Environment variables to pass to the Grafana container"
  type        = map(string)
  default     = null
}