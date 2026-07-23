# provider.tf
# S3 remote state and local/talos providers for the Talos app stack.

terraform {
  backend "s3" {
    key = "talos.tfstate"
  }

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}

provider "local" {}
provider "talos" {}
