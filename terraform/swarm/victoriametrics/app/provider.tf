terraform {
  backend "s3" {
    key = "victoriametrics.tfstate"
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

provider "docker" {
  host     = var.swarm_docker_provider_config.docker.host
  ssh_opts = var.swarm_docker_provider_config.docker.ssh_opts

  dynamic "registry_auth" {
    for_each = coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])

    content {
      address  = try(registry_auth.value.address, "ghcr.io")
      username = registry_auth.value.username
      password = registry_auth.value.password
    }
  }
}
