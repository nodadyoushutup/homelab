variable "provider_config" {
  description = "Provider configuration map for Docker (host + optional ssh opts)."
  type        = any
}

variable "jira_url" {
  description = "Jira base URL."
  type        = string
}

variable "jira_username" {
  description = "Jira username/email."
  type        = string
}

variable "jira_api_token" {
  description = "Jira API token."
  type        = string
  sensitive   = true
}

variable "confluence_url" {
  description = "Confluence base URL."
  type        = string
}

variable "confluence_username" {
  description = "Confluence username/email."
  type        = string
}

variable "confluence_api_token" {
  description = "Confluence API token."
  type        = string
  sensitive   = true
}
