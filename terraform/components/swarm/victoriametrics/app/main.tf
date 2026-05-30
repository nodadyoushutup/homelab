resource "docker_network" "victoriametrics" {
  name   = "victoriametrics-net"
  driver = "overlay"
}

resource "docker_volume" "victoriametrics_data" {
  name   = "victoriametrics-data"
  driver = "local"
}

resource "docker_service" "victoriametrics" {
  name = "victoriametrics"

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
      name    = docker_network.victoriametrics.id
      aliases = ["victoriametrics"]
    }

    container_spec {
      image = "victoriametrics/victoria-metrics:v1.137.0"

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/victoria-metrics-data"
        source = docker_volume.victoriametrics_data.name
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
