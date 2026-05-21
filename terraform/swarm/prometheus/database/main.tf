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
      aliases = ["prometheus-victoriametrics"]
    }

    container_spec {
      image = "victoriametrics/victoria-metrics:v1.137.0"

      args = [
        "-storageDataPath=/prometheus-victoriametrics-data",
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/prometheus-victoriametrics-data"
        source = docker_volume.prometheus_victoriametrics_data.name
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
      target_port    = 8428
      published_port = 8428
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
