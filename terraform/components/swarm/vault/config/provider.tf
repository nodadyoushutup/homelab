# provider.tf
# S3 remote state and Vault provider (auth via VAULT_ADDR/VAULT_TOKEN env) for the Vault config slice.

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
