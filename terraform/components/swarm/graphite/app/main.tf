# main.tf
# Overlay network, storage volume, and Graphite/Carbon/StatsD Swarm service.

resource "docker_network" "graphite" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "graphite_data" {
  name   = local.volume_name
  driver = "local"
}

resource "docker_service" "graphite" {
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
      name    = docker_network.graphite.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "graphiteapp/graphite-statsd:1.1.10-5"

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.storage_mount_target
        source = docker_volume.graphite_data.name
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
    dynamic "ports" {
      for_each = local.ports

      content {
        target_port    = ports.value.target_port
        published_port = ports.value.published_port
        protocol       = ports.value.protocol
        publish_mode   = ports.value.publish_mode
      }
    }
  }
}
