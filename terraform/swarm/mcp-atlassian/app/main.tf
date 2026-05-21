resource "docker_network" "mcp_atlassian" {
  name   = "mcp-atlassian"
  driver = "overlay"
}

resource "docker_service" "mcp_atlassian" {
  name = "mcp-atlassian"

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
      name    = docker_network.mcp_atlassian.id
      aliases = ["mcp-atlassian"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/mcp-atlassian:0.0.2"
      env   = var.env

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
      target_port    = 8000
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
