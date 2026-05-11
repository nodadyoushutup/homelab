terraform {
  backend "s3" {
    key = "chromadb.tfstate"
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

provider "docker" {
  host     = local.provider_config.docker.host
  ssh_opts = local.provider_config.docker.ssh_opts

  dynamic "registry_auth" {
    for_each = local.docker_registry_auths

    content {
      address  = try(registry_auth.value.address, "ghcr.io")
      username = registry_auth.value.username
      password = registry_auth.value.password
    }
  }
}
