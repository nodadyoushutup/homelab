resource "docker_network" "grafana_postgres" {
  name   = "grafana-postgres"
  driver = "overlay"
}

resource "docker_volume" "grafana_postgres_data" {
  name   = "grafana-postgres-data"
  driver = "local"
}

resource "docker_service" "grafana_postgres" {
  name = "grafana-postgres"

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
      name    = docker_network.grafana_postgres.id
      aliases = ["postgres"]
    }

    container_spec {
      image = "postgres:18.3"
      env = {
        POSTGRES_PASSWORD = var.env.POSTGRES_PASSWORD
        POSTGRES_USER     = var.env.POSTGRES_USER
        POSTGRES_DB       = var.env.POSTGRES_DB
      }

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/var/lib/postgresql"
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
      target_port    = 5432
      published_port = 5432
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
