terraform {
  backend "s3" {
    key = "mcp-code.tfstate"
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

provider "docker" {
  host     = var.provider_config.docker.host
  ssh_opts = var.provider_config.docker.ssh_opts

  dynamic "registry_auth" {
    for_each = var.registry_auth == null ? [] : [var.registry_auth]

    content {
      address  = try(registry_auth.value.address, "harbor.nodadyoushutup.com")
      username = registry_auth.value.username
      password = registry_auth.value.password
    }
  }
}
