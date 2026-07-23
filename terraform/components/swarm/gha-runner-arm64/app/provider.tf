# provider.tf
# S3 remote state and Docker provider for the GHA runner (ARM64) pool host.

terraform {
  backend "s3" {
    key = "gha-runner-arm64.tfstate"
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.9.0"
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
