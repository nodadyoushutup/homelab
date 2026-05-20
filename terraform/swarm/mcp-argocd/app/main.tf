resource "docker_network" "mcp_argocd" {
  name   = local.service_name
  driver = "overlay"
}

resource "docker_service" "mcp_argocd" {
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
    dynamic "placement" {
      for_each = var.placement == null ? [] : [var.placement]

      content {
        constraints = try(placement.value.constraints, null)

        dynamic "platforms" {
          for_each = try(placement.value.platforms, [])

          content {
            os           = platforms.value.os
            architecture = platforms.value.architecture
          }
        }
      }
    }
    networks_advanced {
      name    = docker_network.mcp_argocd.id
      aliases = [local.service_name]
    }
    container_spec {
      image   = var.image_reference
      env     = local.effective_env
      command = ["sh", "-c"]
      args = [
        <<-EOT
          if [ "$${ARGOCD_INSECURE_SKIP_VERIFY:-false}" = "true" ]; then
            export NODE_TLS_REJECT_UNAUTHORIZED=0
          fi
          exec node dist/index.js http --port 3000
        EOT
      ]
      dns_config {
        nameservers = var.dns_nameservers
      }
      dynamic "healthcheck" {
        for_each = [local.argocd_healthcheck]
        content {
          test         = healthcheck.value.test
          interval     = try(healthcheck.value.interval, "15s")
          timeout      = try(healthcheck.value.timeout, "5s")
          retries      = try(healthcheck.value.retries, 10)
          start_period = try(healthcheck.value.start_period, "30s")
        }
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
      target_port    = 3000
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
