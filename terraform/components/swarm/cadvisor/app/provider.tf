# provider.tf
# S3 remote state and Docker provider for the cAdvisor Swarm stack.

terraform {
  backend "s3" {
    key = "cadvisor.tfstate"
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

provider "docker" {
  host     = local.swarm_docker_provider_config.docker.host
  ssh_opts = local.swarm_docker_provider_config.docker.ssh_opts

  dynamic "registry_auth" {
    for_each = local.registry_auths

    content {
      address  = try(registry_auth.value.address, local.default_registry_address)
      username = registry_auth.value.username
      password = registry_auth.value.password
    }
  }
}
