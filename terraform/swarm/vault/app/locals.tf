locals {
  stack_name               = "vault"
  data_volume_name         = "vault-data"
  network_name             = "vault"
  service_name             = "vault"
  vault_server_config      = <<-EOT
    ui = true
    disable_mlock = true

    listener "tcp" {
      address         = "0.0.0.0:8200"
      cluster_address = "0.0.0.0:8201"
      tls_disable     = 1
    }

    storage "raft" {
      path    = "/vault/file"
      node_id = "${var.raft_node_id}"
    }

    api_addr     = "${var.api_addr}"
    cluster_addr = "${var.cluster_addr}"
  EOT
  vault_server_config_hash = substr(sha256(local.vault_server_config), 0, 12)
}

locals {
  provider_config = merge(var.swarm_docker_provider_config, var.provider_config)
  docker_registry_auths = (
    try(local.provider_config.registry_auths, null) != null
    ? local.provider_config.registry_auths
    : (
      try(local.provider_config.registry_auth, null) != null
      ? [local.provider_config.registry_auth]
      : []
    )
  )
}
