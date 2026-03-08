locals {
  service_name   = "mcp-fortigate"
  network_name   = "mcp-fortigate"
  internal_port  = 8814
  published_port = 18084
  http_path      = "/mcp"

  has_api_token = var.fortigate_api_token != null && trimspace(var.fortigate_api_token) != ""
  has_user_pass = (
    var.fortigate_username != null && trimspace(var.fortigate_username) != "" &&
    var.fortigate_password != null && trimspace(var.fortigate_password) != ""
  )
}

resource "docker_network" "mcp_fortigate" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_fortigate" {
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
      name    = docker_network.mcp_fortigate.id
      aliases = [local.service_name]
    }

    container_spec {
      image = "homelab/mcp-fortigate:2026.03.08.6"

      env = merge(
        {
          FORTIGATE_HOST       = var.fortigate_host
          FORTIGATE_PORT       = tostring(var.fortigate_port)
          FORTIGATE_VDOM       = var.fortigate_vdom
          FORTIGATE_VERIFY_SSL = tostring(var.fortigate_verify_ssl)
          FORTIGATE_TIMEOUT    = tostring(var.fortigate_timeout)
          MCP_SERVER_PORT      = tostring(local.internal_port)
          MCP_HTTP_PATH        = local.http_path
        },
        local.has_api_token ? { FORTIGATE_API_TOKEN = var.fortigate_api_token } : {},
        local.has_user_pass ? {
          FORTIGATE_USERNAME = var.fortigate_username
          FORTIGATE_PASSWORD = var.fortigate_password
        } : {}
      )

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      healthcheck {
        test = [
          "CMD",
          "python",
          "-c",
          "import socket; s=socket.create_connection(('127.0.0.1', 8814), 5); s.close()",
        ]

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

  lifecycle {
    precondition {
      condition     = local.has_api_token || local.has_user_pass
      error_message = "Set fortigate_api_token or both fortigate_username and fortigate_password in tfvars."
    }
  }
}
