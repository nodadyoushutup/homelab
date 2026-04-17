locals {
  service_name       = "mcp-redis"
  redis_service_name = "mcp-redis-store"
  network_name       = "mcp-redis"
  internal_port      = 8101
  published_port     = 18101
  http_path          = "/mcp"
  image              = "homelab/mcp-redis:2026.04.17.1"
  redis_image        = "redis:7.4.0-alpine"
  redis_url          = "redis://${local.redis_service_name}:6379/${var.redis_database}"
  redis_volume_name  = "mcp-redis-data"
}

resource "docker_network" "mcp_redis" {
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
      name    = docker_network.mcp_redis.id
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

resource "docker_service" "mcp_redis" {
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
      name    = docker_network.mcp_redis.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image

      env = {
        MCP_REDIS_HOST                         = "0.0.0.0"
        MCP_REDIS_LISTEN_PORT                  = tostring(local.internal_port)
        MCP_REDIS_URL                          = local.redis_url
        MCP_REDIS_KEY_PREFIX                   = var.key_prefix
        MCP_REDIS_ALLOWED_HOSTS                = join(",", var.allowed_hosts)
        MCP_REDIS_ALLOWED_ORIGINS              = join(",", var.allowed_origins)
        MCP_REDIS_MAX_SCAN_COUNT               = tostring(var.max_scan_count)
        MCP_REDIS_DEFAULT_EXPIRE_SECONDS       = tostring(var.default_expire_seconds)
        MCP_REDIS_ALLOW_DESTRUCTIVE_OPERATIONS = tostring(var.allow_destructive_operations)
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
