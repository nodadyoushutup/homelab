# provider.tf
# S3 remote state and Cloudflare provider for the Cloudflare DNS config stack.

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
  api_token = var.cloudflare.api_token
}
