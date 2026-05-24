data "docker_network" "prometheus" {
  name = "prometheus"
}

resource "docker_network" "qbittorrent_exporter" {
  name   = "qbittorrent-exporter"
  driver = "overlay"
}

resource "docker_service" "qbittorrent_exporter" {
  for_each = var.instances

  name = "${local.service_name_prefix}-${each.key}"

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
      aliases = ["${local.service_name_prefix}-${each.key}"]
    }

    networks_advanced {
      name = data.docker_network.prometheus.id
    }

    container_spec {
      image = "ghcr.io/martabal/qbittorrent-exporter:v2.0.1"
      env   = local.per_instance_env[each.key]

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
      target_port    = local.internal_port
      published_port = each.value.published_port
      protocol       = "tcp"
      publish_mode   = "host"
    }
  }
}
