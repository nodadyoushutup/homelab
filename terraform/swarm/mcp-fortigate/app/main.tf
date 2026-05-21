resource "docker_network" "mcp_fortigate" {
  name   = "mcp-fortigate"
  driver = "overlay"
}

resource "docker_service" "mcp_fortigate" {
  name = "mcp-fortigate"

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
      name    = docker_network.mcp_fortigate.id
      aliases = ["mcp-fortigate"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/mcp-fortigate:0.0.1"
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
      target_port    = 8814
      published_port = 18205
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
