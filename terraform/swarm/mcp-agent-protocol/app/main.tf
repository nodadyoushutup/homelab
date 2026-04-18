locals {
  service_name       = "mcp-agent-protocol"
  redis_service_name = "agent-protocol-redis"
  network_name       = "mcp-agent-protocol"
  internal_port      = 8100
  published_port     = 18100
  http_path          = "/mcp"
  image              = "homelab/mcp-agent-protocol:2026.04.17.1"
  redis_image        = "redis:7.4.0-alpine"
  redis_url          = "redis://${local.redis_service_name}:6379/${var.redis_database}"
  redis_volume_name  = "mcp-agent-protocol-redis-data"
}

resource "docker_network" "mcp_agent_protocol" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "redis_data" {
  name = local.redis_volume_name
}

resource "docker_service" "redis" {
  name = local.redis_service_name

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.mcp_agent_protocol.id
      aliases = [local.redis_service_name]
    }

    container_spec {
      image = local.redis_image

      command = [
        "redis-server",
        "--appendonly",
        "yes",
        "--save",
        "60",
        "1000",
      ]

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/data"
        source = docker_volume.redis_data.name
        type   = "volume"
      }

      healthcheck {
        test = ["CMD", "redis-cli", "ping"]

        interval     = "30s"
        timeout      = "10s"
        retries      = 5
        start_period = "15s"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }
}

resource "docker_service" "mcp_agent_protocol" {
  name = local.service_name

  depends_on = [docker_service.redis]

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.mcp_agent_protocol.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image

      env = {
        MCP_AGENT_PROTOCOL_HOST                        = "0.0.0.0"
        MCP_AGENT_PROTOCOL_LISTEN_PORT                 = tostring(local.internal_port)
        MCP_AGENT_PROTOCOL_REDIS_URL                   = local.redis_url
        MCP_AGENT_PROTOCOL_KEY_PREFIX                  = var.key_prefix
        MCP_AGENT_PROTOCOL_ALLOWED_HOSTS               = join(",", var.allowed_hosts)
        MCP_AGENT_PROTOCOL_ALLOWED_ORIGINS             = join(",", var.allowed_origins)
        MCP_AGENT_PROTOCOL_DEFAULT_AGENT_TTL_SECONDS   = tostring(var.default_agent_ttl_seconds)
        MCP_AGENT_PROTOCOL_DEFAULT_TASK_TTL_SECONDS    = tostring(var.default_task_ttl_seconds)
        MCP_AGENT_PROTOCOL_COMPLETED_TASK_TTL_SECONDS  = tostring(var.completed_task_ttl_seconds)
        MCP_AGENT_PROTOCOL_DEFAULT_SUMMARY_TTL_SECONDS = tostring(var.default_summary_ttl_seconds)
        MCP_AGENT_PROTOCOL_MESSAGE_LIST_LIMIT          = tostring(var.message_list_limit)
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
}
