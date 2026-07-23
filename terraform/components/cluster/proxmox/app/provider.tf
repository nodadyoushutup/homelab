# provider.tf
# S3 remote state and Proxmox provider for the Proxmox VM/cloud-init stack.

terraform {
  backend "s3" {
    key = "proxmox.tfstate"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
  }
}

provider "proxmox" {
  endpoint      = local.provider_config.proxmox.endpoint
  username      = local.provider_config.proxmox.username
  password      = local.provider_config.proxmox.password
  insecure      = local.provider_config.proxmox.insecure
  random_vm_ids = local.provider_config.proxmox.random_vm_ids
  ssh {
    agent = local.provider_config.proxmox.ssh.agent
  }
}
