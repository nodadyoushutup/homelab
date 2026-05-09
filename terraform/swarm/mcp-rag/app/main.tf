locals {
  service_name  = "mcp-rag"
  internal_port = 8080

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  env_file_pairs = [
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) : {
      key   = trimspace(split("=", trimspace(raw_line))[0])
      value = trimspace(join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line))))))
    }
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  ]
  env_passthrough_keys = toset([
    "LOG_LEVEL",
    "MCP_RAG_API_KEY",
    "MCP_RAG_ENGINE_TIMEOUT_SEC",
    "MCP_RAG_HEALTHCHECK_HOST",
    "MCP_RAG_HEALTHCHECK_PATH",
    "MCP_RAG_HEALTHCHECK_TIMEOUT",
    "MCP_RAG_LOG_LEVEL",
    "RAG_ENGINE_API_KEY",
    "RAG_ENGINE_BASE_URL",
  ])
  parsed_env = {
    for pair in local.env_file_pairs : pair.key => pair.value
    if contains(local.env_passthrough_keys, pair.key)
  }
  default_env = {
    TZ                         = var.timezone
    LOG_LEVEL                  = var.log_level
    MCP_RAG_LOG_LEVEL          = var.log_level
    RAG_ENGINE_BASE_URL        = var.rag_engine_base_url
    MCP_RAG_ENGINE_TIMEOUT_SEC = tostring(var.request_timeout_seconds)
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)
}

data "docker_network" "rag_engine" {
  name = var.rag_engine_network_name
}

resource "docker_service" "mcp_rag" {
  name = local.service_name

  dynamic "auth" {
    for_each = var.registry_auth == null ? [] : [var.registry_auth]

    content {
      server_address = try(auth.value.address, "harbor.nodadyoushutup.com")
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    networks_advanced {
      name    = data.docker_network.rag_engine.id
      aliases = [local.service_name]
    }

    container_spec {
      image = var.image_reference
      env   = local.effective_env

      dns_config {
        nameservers = var.dns_nameservers
      }

      healthcheck {
        test         = ["CMD", "mcp-rag", "healthcheck"]
        interval     = "15s"
        timeout      = "5s"
        retries      = 10
        start_period = "30s"
      }
    }

    restart_policy {
      condition    = "on-failure"
      delay        = "10s"
      max_attempts = 3
      window       = "2m"
    }
  }

  mode {
    replicated {
      replicas = var.replicas
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = local.internal_port
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
