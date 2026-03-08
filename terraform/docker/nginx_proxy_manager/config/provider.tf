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
  url      = var.provider_config.nginx_proxy_manager.url
  username = var.provider_config.nginx_proxy_manager.username
  password = var.provider_config.nginx_proxy_manager.password
}