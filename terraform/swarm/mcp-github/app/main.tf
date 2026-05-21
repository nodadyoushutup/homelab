resource "docker_network" "mcp_github" {
  name   = "mcp-github"
  driver = "overlay"
}

resource "docker_service" "mcp_github" {
  name = "mcp-github"

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
      name    = docker_network.mcp_github.id
      aliases = ["mcp-github"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/mcp-github:0.0.2"
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
      target_port    = 8082
      published_port = 18208
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
