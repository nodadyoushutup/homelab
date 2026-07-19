# provider.tf
# S3 remote state and Jenkins provider for the Jenkins controller config slice.

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
  server_url = var.jenkins.server_url
  username   = var.jenkins.username
  password   = var.jenkins.password
}
