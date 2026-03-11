variable "provider_config" {
  description = "Provider configuration map passed to the Docker provider"
  type        = any
}

variable "db_mysql_host" {
  description = "Internal MySQL hostname for NPM (defaults to Swarm service DNS name)"
  type        = string
  default     = "mysql"
}

variable "env" {
  description = "Additional environment variables to pass to the Nginx Proxy Manager container"
  type        = map(string)
  default     = null
}
