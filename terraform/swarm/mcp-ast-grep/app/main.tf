locals {
  service_name   = "mcp-ast-grep"
  network_name   = "mcp-ast-grep"
  internal_port  = 8096
  published_port = 18096
  http_path      = "/mcp"
  image          = "homelab/mcp-ast-grep:2026.04.16.1"
}

resource "docker_network" "mcp_ast_grep" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_ast_grep" {
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
      name    = docker_network.mcp_ast_grep.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image

      env = {
        AST_GREP_HOST                 = "0.0.0.0"
        AST_GREP_PORT                 = tostring(local.internal_port)
        AST_GREP_DEFAULT_PROJECT_ROOT = var.project_root
        AST_GREP_ALLOWED_ROOTS        = var.project_root
        MCP_HTTP_PATH                 = local.http_path
      }

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target    = var.project_root
        source    = var.repo_mount_path
        type      = "bind"
        read_only = true
      }

      healthcheck {
        test = [
          "CMD",
          "python3",
          "-c",
          "import urllib.error, urllib.request; req=urllib.request.Request('http://127.0.0.1:8096/mcp'); code=0\ntry:\n  urllib.request.urlopen(req, timeout=5)\nexcept urllib.error.HTTPError as e:\n  code=e.code\nexcept Exception:\n  raise SystemExit(1)\nraise SystemExit(0 if code < 500 else 1)",
        ]

        interval     = "30s"
        timeout      = "10s"
        retries      = 5
        start_period = "45s"
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
      condition     = trimspace(var.project_root) != "" && startswith(var.project_root, "/")
      error_message = "project_root must be an absolute container path."
    }
  }
}
