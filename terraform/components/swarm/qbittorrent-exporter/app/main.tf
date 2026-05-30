data "docker_network" "prometheus" {
  name = "prometheus"
}

resource "docker_network" "qbittorrent_exporter" {
  name   = "qbittorrent-exporter"
  driver = "overlay"
}

resource "docker_service" "qbittorrent_exporter" {
  for_each = var.instances

  name = "qbittorrent-exporter-${each.key}"

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
      name    = docker_network.qbittorrent_exporter.id
      aliases = ["qbittorrent-exporter-${each.key}"]
    }

    networks_advanced {
      name = data.docker_network.prometheus.id
    }

    container_spec {
      image = "ghcr.io/martabal/qbittorrent-exporter:v2.0.1"
      env = {
        for key, value in merge(
          var.env,
          { QBITTORRENT_BASE_URL = each.value.base_url },
        ) : key => trimspace(tostring(value))
      }

      dns_config {
        nameservers = var.dns_nameservers
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

  endpoint_spec {
    ports {
      target_port    = 8090
      published_port = each.value.published_port
      protocol       = "tcp"
      publish_mode   = "host"
    }
  }
}
