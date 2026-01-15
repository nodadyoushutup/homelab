terraform {
  backend "s3" {
    key = "graphite.tfstate"
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
  ssh_opts = try(var.provider_config.docker.ssh_opts, [])
}
