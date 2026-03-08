locals {
  service_name   = "mcp-github"
  network_name   = "mcp-github"
  internal_port  = 8082
  published_port = 18082
}

resource "docker_network" "mcp_github" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_github" {
  name = local.service_name

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.mcp_github.id
      aliases = [local.service_name]
    }

    container_spec {
      image = "homelab/mcp-github:2026.03.08.4"

      env = {
        GITHUB_PERSONAL_ACCESS_TOKEN = var.github_personal_access_token
        MCP_GITHUB_LISTEN_PORT       = tostring(local.internal_port)
        GITHUB_MCP_TOOLSETS          = "all"
      }

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      healthcheck {
        test = ["CMD", "python3", "-c", "import socket; s=socket.create_connection(('127.0.0.1', 8082), 5); s.close()"]

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
