# provider.tf
# S3 remote state and Nginx Proxy Manager provider for the config slice.

terraform {
  backend "s3" {
    key = "nginx-proxy-manager-config.tfstate"
  }

  required_providers {
    nginxproxymanager = {
      source  = "Sander0542/nginxproxymanager"
      version = "1.4.0"
    }
  }
}

provider "nginxproxymanager" {
  url      = var.nginx_proxy_manager.url
  username = var.nginx_proxy_manager.username
  password = var.nginx_proxy_manager.password
}
