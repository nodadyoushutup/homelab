locals {
  service_name   = "mcp-filesystem-homelab"
  network_name   = "mcp-filesystem-homelab"
  internal_port  = 8098
  published_port = 18098
  http_path      = "/mcp"
  image          = "homelab/mcp-filesystem-homelab:2026.04.16.3"
}

resource "docker_network" "mcp_filesystem_homelab" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_filesystem_homelab" {
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
      name    = docker_network.mcp_filesystem_homelab.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image
      user  = "${var.runtime_uid}:${var.runtime_gid}"

      env = {
        MCP_FILESYSTEM_HOST           = "0.0.0.0"
        MCP_FILESYSTEM_LISTEN_PORT    = tostring(local.internal_port)
        MCP_FILESYSTEM_WORKSPACE_ROOT = var.workspace_root
      }

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target    = var.workspace_root
        source    = var.repo_mount_path
        type      = "bind"
        read_only = false
      }

      healthcheck {
        test = [
          "CMD",
          "python3",
          "-c",
          "import urllib.error, urllib.request; req=urllib.request.Request('http://127.0.0.1:8098/mcp'); code=0\ntry:\n  urllib.request.urlopen(req, timeout=5)\nexcept urllib.error.HTTPError as e:\n  code=e.code\nexcept Exception:\n  raise SystemExit(1)\nraise SystemExit(0 if code < 500 else 1)",
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
      condition     = trimspace(var.repo_mount_path) != "" && startswith(var.repo_mount_path, "/")
      error_message = "repo_mount_path must be an absolute host path."
    }

    precondition {
      condition     = trimspace(var.workspace_root) != "" && startswith(var.workspace_root, "/")
      error_message = "workspace_root must be an absolute container path."
    }

    precondition {
      condition     = var.runtime_uid > 0 && var.runtime_gid > 0
      error_message = "runtime_uid and runtime_gid must be positive integers."
    }
  }
}
