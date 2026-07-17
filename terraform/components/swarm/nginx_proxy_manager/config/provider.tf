# provider.tf
# S3 remote state and Nginx Proxy Manager provider for the config slice.

terraform {
  backend "s3" {
    key = "nginx-proxy-manager-config.tfstate"
  }

  required_providers {
    nginxproxymanager = {
      source  = "Sander0542/nginxproxymanager"
      version = "1.2.2"
    }
  }
}

provider "nginxproxymanager" {
  url      = local.provider_config.url
  username = local.provider_config.username
  password = local.provider_config.password
}
