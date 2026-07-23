# provider.tf
# S3 remote state and local/talos providers for the Talos app stack.

terraform {
  backend "s3" {
    key = "talos.tfstate"
  }

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
  }
}

provider "local" {}
provider "talos" {}
