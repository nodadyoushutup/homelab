# locals.tf
# Single source of truth for Vault Swarm service values (resources read local.* only).

locals {
  api_addr                     = var.api_addr
  cluster_addr                 = var.cluster_addr
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  published_port               = var.published_port
  raft_node_id                 = var.raft_node_id
  swarm_docker_provider_config = var.swarm_docker_provider_config

  stack_name       = "vault"
  data_volume_name = "vault-data"
  network_name     = "vault"
  service_name     = "vault"

  data_mount            = "/vault/file"
  config_mount          = "/vault/config/vault.hcl"
  listener_addr         = "0.0.0.0:8200"
  cluster_listener_addr = "0.0.0.0:8201"
  target_port           = 8200
  local_vault_addr      = "http://127.0.0.1:8200"

  vault_server_config      = <<-EOT
    ui = true
    disable_mlock = true

    listener "tcp" {
      address         = "${local.listener_addr}"
      cluster_address = "${local.cluster_listener_addr}"
      tls_disable     = 1
    }

    storage "raft" {
      path    = "${local.data_mount}"
      node_id = "${local.raft_node_id}"
    }

    api_addr     = "${local.api_addr}"
    cluster_addr = "${local.cluster_addr}"
  EOT
  vault_server_config_hash = substr(sha256(local.vault_server_config), 0, 12)
  vault_server_config_name = "vault-server-${local.vault_server_config_hash}.hcl"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
