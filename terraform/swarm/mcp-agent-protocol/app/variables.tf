variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "redis_database" {
  description = "Redis database number used by the MCP agent protocol server."
  type        = number
  default     = 0
}

variable "key_prefix" {
  description = "Key prefix used for all Redis entries stored by the MCP server."
  type        = string
  default     = "agent-protocol"
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
    "mcp.agent-protocol.nodadyoushutup.com",
    "mcp.agent-protocol.nodadyoushutup.com:*",
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
    "https://mcp.agent-protocol.nodadyoushutup.com",
  ]
}

variable "default_agent_ttl_seconds" {
  description = "Default TTL for active agent heartbeat records."
  type        = number
  default     = 90
}

variable "default_task_ttl_seconds" {
  description = "Default TTL for active task claims."
  type        = number
  default     = 300
}

variable "completed_task_ttl_seconds" {
  description = "Retention window for completed task records."
  type        = number
  default     = 604800
}

variable "default_summary_ttl_seconds" {
  description = "Default TTL for short-lived summaries."
  type        = number
  default     = 86400
}

variable "message_list_limit" {
  description = "Maximum recent messages to retain in Redis lists."
  type        = number
  default     = 200
}
