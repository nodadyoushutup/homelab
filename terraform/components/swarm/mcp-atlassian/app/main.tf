# main.tf
# Overlay network and mcp-atlassian Swarm service.

resource "docker_network" "mcp_atlassian" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_atlassian" {
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
      name    = docker_network.mcp_atlassian.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/nodadyoushutup/mcp-atlassian:0.0.5"
      env   = local.env

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
      target_port    = local.service_port.target_port
      published_port = local.service_port.published_port
      protocol       = local.service_port.protocol
      publish_mode   = local.service_port.publish_mode
    }
  }
}
