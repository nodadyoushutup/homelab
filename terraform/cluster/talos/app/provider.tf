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
      version = "0.10.1"
    }
  }
}

provider "local" {}
provider "talos" {}
