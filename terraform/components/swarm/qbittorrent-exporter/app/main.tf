# main.tf
# Overlay network and per-instance qBittorrent exporter Swarm services.

data "docker_network" "prometheus" {
  name = local.prometheus_network_name
}

resource "docker_network" "qbittorrent_exporter" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "qbittorrent_exporter" {
  for_each = local.instances

  name = "${local.service_name_prefix}-${each.key}"

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
      name    = docker_network.qbittorrent_exporter.id
      aliases = ["${local.service_name_prefix}-${each.key}"]
    }

    networks_advanced {
      name = data.docker_network.prometheus.id
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/martabal/qbittorrent-exporter:v2.0.1"
      env = {
        for key, value in merge(
          local.env,
          { QBITTORRENT_BASE_URL = each.value.base_url },
        ) : key => trimspace(tostring(value))
      }

      dns_config {
        nameservers = local.dns_nameservers
      }
    }
  }

  mode {
    replicated {
      replicas = local.replicas
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = local.container_port
      published_port = each.value.published_port
      protocol       = "tcp"
      publish_mode   = "host"
    }
  }
}
