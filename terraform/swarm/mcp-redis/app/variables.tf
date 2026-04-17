variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "redis_database" {
  description = "Redis database number used by the Redis MCP server."
  type        = number
  default     = 0
}

variable "key_prefix" {
  description = "Logical key prefix applied automatically by the Redis MCP server."
  type        = string
  default     = "shared"
}

variable "allowed_hosts" {
  description = "Allowed Host header values for MCP transport security."
  type        = list(string)
  default = [
    "127.0.0.1",
    "127.0.0.1:*",
    "localhost",
    "localhost:*",
    "[::1]",
    "[::1]:*",
    "swarm-cp-0.local",
    "swarm-cp-0.local:*",
    "mcp.redis.nodadyoushutup.com",
    "mcp.redis.nodadyoushutup.com:*",
  ]
}

variable "allowed_origins" {
  description = "Allowed Origin header values for MCP transport security."
  type        = list(string)
  default = [
    "http://127.0.0.1",
    "http://127.0.0.1:*",
    "http://localhost",
    "http://localhost:*",
    "http://[::1]",
    "http://[::1]:*",
    "http://swarm-cp-0.local",
    "http://swarm-cp-0.local:*",
    "https://mcp.redis.nodadyoushutup.com",
  ]
}

variable "max_scan_count" {
  description = "Maximum count value allowed for Redis scan-like operations."
  type        = number
  default     = 200
}

variable "default_expire_seconds" {
  description = "Default expiry guidance returned by the Redis MCP server."
  type        = number
  default     = 86400
}

variable "allow_destructive_operations" {
  description = "Whether delete operations are allowed through the Redis MCP server."
  type        = bool
  default     = true
}
