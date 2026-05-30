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
  url      = var.provider_config.url
  username = var.provider_config.username
  password = var.provider_config.password
}
