data "docker_network" "rag_engine" {
  name = "rag-engine"
}

resource "docker_service" "mcp_rag" {
  name = "mcp-rag"

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
      name    = data.docker_network.rag_engine.id
      aliases = ["mcp-rag"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/mcp-rag:0.0.4"
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
      target_port    = 8080
      published_port = 9016
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
