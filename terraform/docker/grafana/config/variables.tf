variable "provider_config" {
  description = "Provider configuration map (grafana credentials + optional docker host)"
  type        = any
}

variable "datasources" {
  description = "Optional list of Grafana data sources to manage"
  type        = list(any)
  default     = []
}
