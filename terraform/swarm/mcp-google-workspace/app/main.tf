locals {
  service_name            = "mcp-google-workspace"
  network_name            = "mcp-google-workspace"
  internal_port           = 8086
  published_port          = 18092
  service_account_target  = "/run/workspace-mcp/service_account.json"
  has_workspace_tools_env = var.workspace_tools != null && trimspace(var.workspace_tools) != ""
}

resource "docker_network" "mcp_google_workspace" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_google_workspace" {
  name = local.service_name

  dynamic "auth" {
    for_each = try(var.provider_config.registry_auth, null) == null ? [] : [var.provider_config.registry_auth]

    content {
      server_address = try(auth.value.address, "ghcr.io")
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
      name    = docker_network.mcp_google_workspace.id
      aliases = [local.service_name]
    }

    container_spec {
      image = "homelab/mcp-google-workspace:2026.03.09.1"

      env = merge(
        {
          MCP_GOOGLE_WORKSPACE_LISTEN_PORT   = tostring(local.internal_port)
          WORKSPACE_MCP_DELEGATED_USER       = var.workspace_delegated_user
          WORKSPACE_MCP_SERVICE_ACCOUNT_FILE = local.service_account_target
          GOOGLE_WORKSPACE_MCP_TOOL_TIER     = var.workspace_tool_tier
          GOOGLE_WORKSPACE_MCP_READ_ONLY     = tostring(var.workspace_read_only)
        },
        local.has_workspace_tools_env ? {
          GOOGLE_WORKSPACE_MCP_TOOLS = var.workspace_tools
        } : {}
      )

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        type      = "bind"
        source    = var.workspace_service_account_file
        target    = local.service_account_target
        read_only = true
      }

      healthcheck {
        test = [
          "CMD",
          "python3",
          "-c",
          "import socket; s=socket.create_connection(('127.0.0.1', 8086), 5); s.close()",
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
      condition     = can(regex(".+@.+", var.workspace_delegated_user))
      error_message = "workspace_delegated_user must be a valid email address."
    }

    precondition {
      condition     = trimspace(var.workspace_service_account_file) != ""
      error_message = "workspace_service_account_file must be set to the host path of service_account.json."
    }
  }
}
