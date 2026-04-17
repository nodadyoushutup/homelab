locals {
  service_name   = "mcp-terraform"
  network_name   = "mcp-terraform"
  internal_port  = 8080
  published_port = 18104
  http_path      = "/mcp"
  health_path    = "/health"
  image          = "homelab/mcp-terraform:2026.04.16.1"

  runtime_env = merge(
    {
      ENABLE_TF_OPERATIONS = tostring(var.enable_tf_operations)
      MCP_CORS_MODE        = var.mcp_cors_mode
    },
    var.tfe_address == null || trimspace(var.tfe_address) == "" ? {} : {
      TFE_ADDRESS = var.tfe_address
    },
    var.tfe_token == null || trimspace(var.tfe_token) == "" ? {} : {
      TFE_TOKEN = var.tfe_token
    },
    var.mcp_allowed_origins == null || trimspace(var.mcp_allowed_origins) == "" ? {} : {
      MCP_ALLOWED_ORIGINS = var.mcp_allowed_origins
    }
  )

  base_args = [
    "streamable-http",
    "--transport-host", "0.0.0.0",
    "--transport-port", tostring(local.internal_port),
    "--mcp-endpoint", local.http_path,
    "--toolsets", var.toolsets,
  ]
}

resource "docker_network" "mcp_terraform" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_terraform" {
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
      name    = docker_network.mcp_terraform.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image
      args  = local.base_args

      env = local.runtime_env

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
          "wget",
          "-q",
          "-O",
          "/dev/null",
          "http://127.0.0.1:8080/health",
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
      condition     = trimspace(var.toolsets) != ""
      error_message = "toolsets must not be empty."
    }

    precondition {
      condition     = contains(["strict", "development", "disabled"], var.mcp_cors_mode)
      error_message = "mcp_cors_mode must be one of strict, development, or disabled."
    }
  }
}
