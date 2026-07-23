# main.tf
# Overlay network, config, volume, and Grafana Swarm service wired to Postgres and VictoriaMetrics.

data "docker_network" "grafana_postgres" {
  name = local.postgres_network_name
}

data "docker_network" "victoriametrics" {
  name = local.victoriametrics_network_name
}

resource "docker_network" "grafana_app" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "grafana_app" {
  name   = local.volume_name
  driver = "local"
}

resource "docker_config" "grafana_app" {
  name = local.config_name
  data = filebase64(local.ini_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "grafana" {
  name = local.service_name

  task_spec {
    force_update = local.ini_force_update

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
      name    = docker_network.grafana_app.id
      aliases = [local.network_alias]
    }

    networks_advanced {
      name    = data.docker_network.grafana_postgres.id
      aliases = []
    }

    networks_advanced {
      name    = data.docker_network.victoriametrics.id
      aliases = []
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "grafana/grafana:12.4.6"
      env   = local.env

      mounts {
        target = local.data_mount
        source = docker_volume.grafana_app.name
        type   = "volume"
      }

      configs {
        config_id   = docker_config.grafana_app.id
        config_name = docker_config.grafana_app.name
        file_name   = local.ini_mount
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
}
