# main.tf
# Overlay network and global cAdvisor Swarm service (host-published metrics).

resource "docker_network" "cadvisor" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "cadvisor" {
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
      name    = docker_network.cadvisor.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/google/cadvisor:v0.60.5"
      args  = local.args

      dns_config {
        nameservers = local.dns_nameservers
      }

      dynamic "mounts" {
        for_each = local.mounts

        content {
          target    = mounts.value.target
          source    = mounts.value.source
          type      = mounts.value.type
          read_only = mounts.value.read_only
        }
      }
    }
  }

  mode {
    global = true
  }

  endpoint_spec {
    ports {
      target_port    = local.metrics_port
      published_port = local.metrics_port
      publish_mode   = "host"
    }
  }
}
