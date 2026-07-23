# main.tf
# Overlay network plus agentmemory backend and mcp-agentmemory bridge Swarm services.

resource "docker_network" "mcp_agentmemory" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "agentmemory_data" {
  name   = local.agentmemory_volume_name
  driver = "local"
}

resource "docker_service" "agentmemory" {
  name = local.agentmemory_service_name

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
      name    = docker_network.mcp_agentmemory.id
      aliases = [local.agentmemory_network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/nodadyoushutup/agentmemory:0.0.2"
      env   = local.agentmemory_env

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.agentmemory_data.name
        target = local.agentmemory_data_mount
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
}

resource "docker_service" "mcp_agentmemory" {
  name = local.mcp_service_name

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
      name    = docker_network.mcp_agentmemory.id
      aliases = [local.mcp_network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/nodadyoushutup/mcp-agentmemory:0.0.2"
      env   = local.mcp_agentmemory_env

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
      target_port    = local.mcp_target_port
      published_port = local.mcp_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }

  depends_on = [docker_service.agentmemory]
}
