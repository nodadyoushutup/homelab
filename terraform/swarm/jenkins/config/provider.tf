terraform {
  backend "s3" {
    key = "jenkins-config.tfstate"
  }

  required_providers {
    jenkins = {
      source  = "taiidani/jenkins"
      version = "0.11.0"
    }
  }
}

provider "jenkins" {
  server_url = var.provider_config.jenkins.server_url
  username   = var.provider_config.jenkins.username
  password   = var.provider_config.jenkins.password
}
