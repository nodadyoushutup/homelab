resource "docker_network" "mcp_github" {
  name   = local.service_name
  driver = "overlay"
}

resource "docker_service" "mcp_github" {
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
      name    = docker_network.mcp_github.id
      aliases = [local.service_name]
    }
    container_spec {
      image = var.image_reference
      env   = local.effective_env
      dns_config {
        nameservers = var.dns_nameservers
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
      target_port    = 8082
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
