# provider.tf
# S3 remote state and fortios provider for the FortiGate config stack.

terraform {
  backend "s3" {
    key = "fortigate-config.tfstate"
  }

  required_providers {
    fortios = {
      source  = "fortinetdev/fortios"
      version = "~> 1.25.0"
    }
  }
}

provider "fortios" {
  hostname = local.fortigate_hostname
  insecure = local.fortigate_insecure
  vdom     = local.fortigate_vdom

  token    = local.fortigate_has_token ? local.fortigate_api_token : null
  username = local.fortigate_has_token ? null : local.fortigate_username
  password = local.fortigate_has_token ? null : local.fortigate_password
}
