locals {
  service_name   = "mcp-cloudflare"
  network_name   = "mcp-cloudflare"
  internal_port  = 8084
  published_port = 18090

  has_email = var.cloudflare_email != null && trimspace(var.cloudflare_email) != ""
}

resource "docker_network" "mcp_cloudflare" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_cloudflare" {
  name = local.service_name

  dynamic "auth" {
    for_each = try(var.provider_config.registry_auth, null) == null ? [] : [var.provider_config.registry_auth]

    content {
      server_address = try(auth.value.address, "harbor.nodadyoushutup.com")
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.mcp_cloudflare.id
      aliases = [local.service_name]
    }

    container_spec {
      image = "harbor.nodadyoushutup.com/mcp-cloudflare/mcp-cloudflare:0.0.1"

      env = merge(
        {
          CLOUDFLARE_API_TOKEN       = var.cloudflare_api_token
          CLOUDFLARE_ZONE_ID         = var.cloudflare_zone_id
          MCP_CLOUDFLARE_LISTEN_PORT = tostring(local.internal_port)
        },
        local.has_email ? { CLOUDFLARE_EMAIL = var.cloudflare_email } : {}
      )

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      healthcheck {
        test = ["CMD", "python3", "-c", "import socket; s=socket.create_connection(('127.0.0.1', 8084), 5); s.close()"]

        interval     = "30s"
        timeout      = "10s"
        retries      = 5
        start_period = "30s"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  endpoint_spec {
    ports {
      target_port    = local.internal_port
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
