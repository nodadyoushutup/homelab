# main.tf
# Overlay network, data/config volumes, and replicated graylog-mongodb Swarm service.

resource "docker_network" "graylog_mongodb" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "graylog_mongodb_data" {
  name = local.data_volume_name
}

resource "docker_volume" "graylog_mongodb_config" {
  name = local.config_volume_name
}

resource "docker_service" "graylog_mongodb" {
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
      name    = docker_network.graylog_mongodb.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "mongo:8.3.7"

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.data_mount
        source = docker_volume.graylog_mongodb_data.name
        type   = "volume"
      }

      mounts {
        target = local.config_mount
        source = docker_volume.graylog_mongodb_config.name
        type   = "volume"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  update_config {
    order = "stop-first"
  }
}
