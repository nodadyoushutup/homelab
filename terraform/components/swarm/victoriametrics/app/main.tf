# main.tf
# Overlay network, storage volume, and VictoriaMetrics Swarm service.

resource "docker_network" "victoriametrics" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "victoriametrics_data" {
  name   = local.volume_name
  driver = "local"
}

resource "docker_service" "victoriametrics" {
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
      name    = docker_network.victoriametrics.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "victoriametrics/victoria-metrics:v1.137.0"

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.storage_mount_target
        source = docker_volume.victoriametrics_data.name
        type   = "volume"
      }
    }
  }

  mode {
    replicated {
      replicas = local.replicas
    }
  }

  endpoint_spec {
    ports {
      target_port    = local.http_port.target_port
      published_port = local.http_port.published_port
      protocol       = local.http_port.protocol
      publish_mode   = local.http_port.publish_mode
    }
  }
}
