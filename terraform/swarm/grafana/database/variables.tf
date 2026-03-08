variable "provider_config" {
  description = "Provider configuration map passed to the Docker provider"
  type        = any
}

variable "env" {
  description = "Additional environment variables to pass to the Nginx Proxy Manager container"
  type        = map(string)
  default     = null
}