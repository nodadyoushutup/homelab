resource "docker_network" "vault" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "vault_data" {
  name   = local.data_volume_name
  driver = "local"
}

resource "docker_config" "vault_server" {
  name = "vault-server-${local.vault_server_config_hash}.hcl"
  data = base64encode(local.vault_server_config)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "vault" {
  name = local.service_name

  task_spec {
    dynamic "placement" {
      for_each = var.placement == null ? [] : [var.placement]

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
      image = "hashicorp/vault:1.21.4@sha256:4e33b126a59c0c333b76fb4e894722462659a6bec7c48c9ee8cea56fccfd2569"
      args  = ["server"]
      env = {
        VAULT_ADDR = "http://127.0.0.1:8200"
      }

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.vault_data.name
        target = "/vault/file"
      }

      configs {
        config_id   = docker_config.vault_server.id
        config_name = docker_config.vault_server.name
        file_name   = "/vault/config/vault.hcl"
      }

      healthcheck {
        test         = ["CMD-SHELL", "VAULT_ADDR=http://127.0.0.1:8200 vault status >/dev/null 2>&1; code=$?; [ \"$code\" -eq 0 ] || [ \"$code\" -eq 1 ] || [ \"$code\" -eq 2 ]"]
        interval     = "15s"
        timeout      = "5s"
        retries      = 10
        start_period = "30s"
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
      target_port    = 8200
      published_port = var.published_port
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
