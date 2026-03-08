terraform {
  backend "s3" {
    key = "jenkins-controller.tfstate"
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
}

provider "jenkins" {
  server_url = var.provider_config.jenkins.server_url
  username   = var.provider_config.jenkins.username
  password   = var.provider_config.jenkins.password
}
