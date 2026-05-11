terraform {
  backend "s3" {
    key = "harbor-config.tfstate"
  }

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.10"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "harbor" {
  url          = var.provider_config.harbor.url
  username     = var.provider_config.harbor.username
  password     = try(var.provider_config.harbor.password, null)
  bearer_token = try(var.provider_config.harbor.bearer_token, null)
  session_id   = try(var.provider_config.harbor.session_id, null)
  insecure     = try(var.provider_config.harbor.insecure, null)
  api_version  = try(var.provider_config.harbor.api_version, null)
  robot_prefix = try(var.provider_config.harbor.robot_prefix, null)
}
