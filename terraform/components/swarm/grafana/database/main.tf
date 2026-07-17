# main.tf
# Overlay network, data volume, and replicated grafana-postgres Swarm service.

resource "docker_network" "grafana_postgres" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "grafana_postgres_data" {
  name   = local.volume_name
  driver = "local"
}

resource "docker_service" "grafana_postgres" {
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
      name    = docker_network.grafana_postgres.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "postgres:18.3"
      env = {
        POSTGRES_PASSWORD = local.env.POSTGRES_PASSWORD
        POSTGRES_USER     = local.env.POSTGRES_USER
        POSTGRES_DB       = local.env.POSTGRES_DB
      }

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.data_mount
        source = docker_volume.grafana_postgres_data.name
        type   = "volume"
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
      target_port    = local.postgres_port
      published_port = local.postgres_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
