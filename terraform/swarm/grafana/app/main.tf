data "docker_network" "grafana_postgres" {
  name = "grafana-postgres"
}

resource "docker_network" "grafana_app" {
  name   = "grafana-app"
  driver = "overlay"
}

resource "docker_volume" "grafana_app" {
  name   = "grafana-app"
  driver = "local"
}

resource "docker_config" "grafana_app" {
  name = "grafana-ini-${local.grafana_ini_hash}"
  data = filebase64(var.ini_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "grafana" {
  name = "grafana"

  task_spec {
    force_update = local.grafana_ini_force_update

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
      name    = docker_network.grafana_app.id
      aliases = ["grafana"]
    }

    networks_advanced {
      name    = data.docker_network.grafana_postgres.id
      aliases = []
    }

    container_spec {
      image = "grafana/grafana:12.3.1@sha256:2175aaa91c96733d86d31cf270d5310b278654b03f5718c59de12a865380a31f"
      env   = var.env

      mounts {
        target = "/var/lib/grafana"
        source = docker_volume.grafana_app.name
        type   = "volume"
      }

      configs {
        config_id   = docker_config.grafana_app.id
        config_name = docker_config.grafana_app.name
        file_name   = "/etc/grafana/grafana.ini"
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
      target_port    = 3000
      published_port = 3000
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
