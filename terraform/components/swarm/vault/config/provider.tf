# provider.tf
# S3 remote state and Vault provider for the Vault config slice. Provider login
# comes from var.vault (config-id terraform/providers/vault), a shared -var-file
# managed by the homelab-config web app.

terraform {
  backend "s3" {
    key = "vault-config.tfstate"
  }

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.10.1"
    }
  }
}

provider "vault" {
  address         = var.vault.address
  token           = var.vault.token
  skip_tls_verify = try(var.vault.skip_tls_verify, false)
}
