terraform {
  backend "s3" {
    key = "proxmox.tfstate"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.97.1"
    }
  }
}

provider "proxmox" {
  endpoint      = var.provider_config.proxmox.endpoint
  username      = var.provider_config.proxmox.username
  password      = var.provider_config.proxmox.password
  insecure      = var.provider_config.proxmox.insecure
  random_vm_ids = var.provider_config.proxmox.random_vm_ids
  ssh {
    agent = var.provider_config.proxmox.ssh.agent
  }
}
