locals {
  service_name   = "mcp-langflow"
  network_name   = "mcp-langflow"
  internal_port  = 8102
  published_port = 18102
  http_path      = "/mcp"
  image          = "homelab/mcp-langflow:2026.04.17.1"
}

resource "docker_network" "mcp_langflow" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_langflow" {
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
      name    = docker_network.mcp_langflow.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image

      env = {
        MCP_LANGFLOW_HOST             = "0.0.0.0"
        MCP_LANGFLOW_LISTEN_PORT      = tostring(local.internal_port)
        LANGFLOW_BASE_URL             = var.langflow_base_url
        LANGFLOW_API_KEY              = var.langflow_api_key
        LANGFLOW_TIMEOUT              = tostring(var.langflow_timeout)
        LANGFLOW_CONSOLIDATED_TOOLS   = tostring(var.langflow_consolidated_tools)
        ENABLE_DEPRECATED_TOOLS       = tostring(var.enable_deprecated_tools)
        LOG_LEVEL                     = "error"
        DOTENV_CONFIG_QUIET           = "true"
        MCP_MODE                      = "stdio"
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
          "python3",
          "-c",
          "import urllib.error, urllib.request; req=urllib.request.Request('http://127.0.0.1:${local.internal_port}${local.http_path}'); code=0\ntry:\n  urllib.request.urlopen(req, timeout=5)\nexcept urllib.error.HTTPError as e:\n  code=e.code\nexcept Exception:\n  raise SystemExit(1)\nraise SystemExit(0 if code < 500 else 1)",
        ]

        interval     = "30s"
        timeout      = "10s"
        retries      = 5
        start_period = "20s"
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
      condition     = can(regex("^https?://", trimspace(var.langflow_base_url)))
      error_message = "langflow_base_url must start with http:// or https://."
    }

    precondition {
      condition     = length(trimspace(var.langflow_api_key)) >= 10
      error_message = "langflow_api_key must look like a real Langflow API key."
    }
  }
}
