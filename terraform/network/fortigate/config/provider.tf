terraform {
  backend "s3" {
    key = "fortigate-config.tfstate"
  }

  required_providers {
    fortios = {
      source  = "fortinetdev/fortios"
      version = "~> 1.24.0"
    }
  }
}

locals {
  fortigate_host        = trimspace(var.provider_config.fortigate.host)
  fortigate_port        = try(var.provider_config.fortigate.port, 443)
  fortigate_hostname    = local.fortigate_port == 443 ? local.fortigate_host : "${local.fortigate_host}:${local.fortigate_port}"
  fortigate_api_token   = try(trimspace(var.provider_config.fortigate.api_token), "")
  fortigate_username    = try(trimspace(var.provider_config.fortigate.username), "")
  fortigate_password    = try(trimspace(var.provider_config.fortigate.password), "")
  fortigate_has_token   = local.fortigate_api_token != ""
  fortigate_has_userpwd = local.fortigate_username != "" && local.fortigate_password != ""
}

provider "fortios" {
  hostname = local.fortigate_hostname
  insecure = try(var.provider_config.fortigate.insecure, true)
  vdom     = try(var.provider_config.fortigate.vdom, "root")

  token    = local.fortigate_has_token ? local.fortigate_api_token : null
  username = local.fortigate_has_token ? null : local.fortigate_username
  password = local.fortigate_has_token ? null : local.fortigate_password
}
