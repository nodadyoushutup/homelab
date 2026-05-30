terraform {
  backend "s3" {
    key = "vault-config.tfstate"
  }

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.7.0"
    }
  }
}

provider "vault" {}
