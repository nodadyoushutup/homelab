# main.tf
# Overlay network, raft data volume, server config, and Vault Swarm service.

resource "docker_network" "vault" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "vault_data" {
  name   = local.data_volume_name
  driver = "local"
}

resource "docker_config" "vault_server" {
  name = local.vault_server_config_name
  data = base64encode(local.vault_server_config)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "vault" {
  name = local.service_name

  task_spec {
    dynamic "placement" {
      for_each = local.placement == null ? [] : [local.placement]

      content {
        constraints = try(placement.value.constraints, null)

        dynamic "platforms" {
          for_each = try(placement.value.platforms, [])

          content {
            os           = platforms.value.os
            architecture = platforms.value.architecture
          }
        }
      }
    }

    networks_advanced {
      name    = docker_network.vault.id
      aliases = [local.service_name]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "hashicorp/vault:2.0.3"
      args  = ["server"]
      env = {
        VAULT_ADDR = local.local_vault_addr
      }

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.vault_data.name
        target = local.data_mount
      }

      configs {
        config_id   = docker_config.vault_server.id
        config_name = docker_config.vault_server.name
        file_name   = local.config_mount
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  endpoint_spec {
    ports {
      target_port    = local.target_port
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }

  lifecycle {
    replace_triggered_by = [
      docker_config.vault_server,
    ]
  }
}
