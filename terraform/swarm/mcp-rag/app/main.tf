data "docker_network" "rag_engine" {
  name = var.rag_engine_network_name
}

resource "docker_service" "mcp_rag" {
  name = local.service_name

  dynamic "auth" {
    for_each = local.docker_service_pull_auth_map

    content {
      server_address = auth.value.server_address
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
