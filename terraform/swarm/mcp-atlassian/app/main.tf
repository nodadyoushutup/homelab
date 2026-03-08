locals {
  service_name   = "mcp-atlassian"
  network_name   = "mcp-atlassian"
  internal_port  = 8000
  published_port = 18080
  http_path      = "/mcp"
}

resource "docker_network" "mcp_atlassian" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_atlassian" {
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
      name    = docker_network.mcp_atlassian.id
      aliases = [local.service_name]
    }

    container_spec {
      image = "ghcr.io/sooperset/mcp-atlassian:latest@sha256:6c4f96725b0e775a014a0b3016d358efdab58efd57c37ad7c2050136545b0e00"

      args = [
        "--transport", "streamable-http",
        "--host", "0.0.0.0",
        "--port", tostring(local.internal_port),
        "--path", local.http_path,
        "--read-only",
        "--toolsets", "jira,confluence",
      ]

      env = {
        JIRA_URL             = var.jira_url
        JIRA_USERNAME        = var.jira_username
        JIRA_API_TOKEN       = var.jira_api_token
        CONFLUENCE_URL       = var.confluence_url
        CONFLUENCE_USERNAME  = var.confluence_username
        CONFLUENCE_API_TOKEN = var.confluence_api_token
      }

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
          "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/mcp', timeout=5)",
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
}
