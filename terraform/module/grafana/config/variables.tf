variable "datasources" {
  description = "Optional list of Grafana data sources to manage."
  type        = list(any)
  default     = []
}
