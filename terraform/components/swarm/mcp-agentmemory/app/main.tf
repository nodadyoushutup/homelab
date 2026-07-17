resource "docker_network" "mcp_agentmemory" {
  name   = "mcp-agentmemory"
  driver = "overlay"
}

resource "docker_volume" "agentmemory_data" {
  name   = "agentmemory-data"
  driver = "local"
}

resource "docker_service" "agentmemory" {
  name = "agentmemory"

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
      name    = docker_network.mcp_agentmemory.id
      aliases = ["agentmemory"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/agentmemory:0.0.1"
      env   = local.agentmemory_env

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.agentmemory_data.name
        target = "/data"
      }
    }
  }

  mode {
    replicated {
      replicas = var.replicas
    }
  }

  update_config {
    order = "stop-first"
  }
}

resource "docker_service" "mcp_agentmemory" {
  name = "mcp-agentmemory"

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
      name    = docker_network.mcp_agentmemory.id
      aliases = ["mcp-agentmemory"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/mcp-agentmemory:0.0.1"
      env   = local.mcp_agentmemory_env

      dns_config {
        nameservers = var.dns_nameservers
      }
    }
  }

  mode {
    replicated {
      replicas = var.replicas
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = 8087
      published_port = 18212
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }

  depends_on = [docker_service.agentmemory]
}
