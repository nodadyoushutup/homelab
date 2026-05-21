resource "docker_network" "prometheus_victoriametrics" {
  name   = "prometheus-victoriametrics"
  driver = "overlay"
}

resource "docker_volume" "prometheus_victoriametrics_data" {
  name   = "prometheus-victoriametrics-data"
  driver = "local"
}

resource "docker_service" "prometheus_victoriametrics" {
  name = "prometheus-victoriametrics"

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
      name    = docker_network.prometheus_victoriametrics.id
      aliases = ["victoriametrics"]
    }

    container_spec {
      image = "victoriametrics/victoria-metrics:v1.137.0"

      args = [
        "-storageDataPath=/victoria-metrics-data",
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/victoria-metrics-data"
        source = docker_volume.prometheus_victoriametrics_data.name
        type   = "volume"
      }

      healthcheck {
        test         = ["CMD", "wget", "--spider", "--quiet", "http://127.0.0.1:8428/health"]
        interval     = "10s"
        timeout      = "5s"
        retries      = 6
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
      target_port    = 8428
      published_port = 8428
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
