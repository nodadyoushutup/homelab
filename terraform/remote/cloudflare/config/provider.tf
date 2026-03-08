terraform {
  backend "s3" {
    key = "cloudflare-config.tfstate"
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.provider_config.cloudflare.api_token
}
