# main.tf
# Overlay network and Dozzle Swarm log viewer service.

resource "docker_network" "dozzle" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "dozzle" {
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
      name    = docker_network.dozzle.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "amir20/dozzle:v10.6.11"

      env = local.env

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.docker_sock_path
        source = local.docker_sock_path
        type   = "bind"
      }
    }
  }

  mode {
    global = true
  }

  endpoint_spec {
    ports {
      target_port    = local.ui_port.target_port
      published_port = local.ui_port.published_port
      publish_mode   = local.ui_port.publish_mode
    }
  }
}
