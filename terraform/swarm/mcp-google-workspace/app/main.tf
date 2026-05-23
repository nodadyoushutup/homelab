resource "docker_network" "mcp_google_workspace" {
  name   = "mcp-google-workspace"
  driver = "overlay"
}

resource "docker_service" "mcp_google_workspace" {
  name = "mcp-google-workspace"

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
      name    = docker_network.mcp_google_workspace.id
      aliases = ["mcp-google-workspace"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/mcp-google-workspace:0.0.1"
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
      target_port    = 8086
      published_port = 18209
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
