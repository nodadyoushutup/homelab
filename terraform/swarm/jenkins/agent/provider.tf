terraform {
  backend "s3" {
    key = "jenkins-agent.tfstate"
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
    jenkins = {
      source  = "taiidani/jenkins"
      version = "0.11.0"
    }
  }
}

provider "docker" {
  host     = var.provider_config.docker.host
  ssh_opts = var.provider_config.docker.ssh_opts

  dynamic "registry_auth" {
    for_each = try(var.provider_config.registry_auth, null) == null ? [] : [var.provider_config.registry_auth]

    content {
      address  = try(registry_auth.value.address, "ghcr.io")
      username = registry_auth.value.username
      password = registry_auth.value.password
    }
  }
}

provider "jenkins" {
  server_url = var.provider_config.jenkins.server_url
  username   = var.provider_config.jenkins.username
  password   = var.provider_config.jenkins.password
}
