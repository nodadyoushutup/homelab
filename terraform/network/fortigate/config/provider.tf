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

provider "fortios" {
  hostname = local.fortigate_hostname
  insecure = try(var.provider_config.fortigate.insecure, true)
  vdom     = try(var.provider_config.fortigate.vdom, "root")

  token    = local.fortigate_has_token ? local.fortigate_api_token : null
  username = local.fortigate_has_token ? null : local.fortigate_username
  password = local.fortigate_has_token ? null : local.fortigate_password
}
