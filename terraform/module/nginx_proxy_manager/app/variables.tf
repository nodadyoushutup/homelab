variable "provider_config" {
  description = "Docker provider configuration"
  type        = any
}

variable "env" {
  description = "Additional environment variables to pass to the Nginx Proxy Manager container"
  type        = map(string)
  default     = null
}