variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "fortigate_host" {
  description = "FortiGate management hostname or IP address."
  type        = string
}

variable "fortigate_port" {
  description = "FortiGate API HTTPS port."
  type        = number
  default     = 443
}

variable "fortigate_vdom" {
  description = "FortiGate VDOM used for API operations."
  type        = string
  default     = "root"
}

variable "fortigate_verify_ssl" {
  description = "Whether to verify FortiGate TLS certificates."
  type        = bool
  default     = false
}

variable "fortigate_timeout" {
  description = "FortiGate API timeout in seconds."
  type        = number
  default     = 30
}

variable "fortigate_api_token" {
  description = "FortiGate API token. Leave null when using username/password auth."
  type        = string
  default     = null
  sensitive   = true
}

variable "fortigate_username" {
  description = "FortiGate username. Used when API token is not provided."
  type        = string
  default     = null
}

variable "fortigate_password" {
  description = "FortiGate password. Used when API token is not provided."
  type        = string
  default     = null
  sensitive   = true
}
