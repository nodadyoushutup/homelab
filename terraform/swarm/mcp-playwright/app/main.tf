resource "docker_network" "mcp_playwright" {
  name   = "mcp-playwright"
  driver = "overlay"
}

resource "docker_service" "mcp_playwright" {
  name = "mcp-playwright"

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
      name    = docker_network.mcp_playwright.id
      aliases = ["mcp-playwright"]
    }

    container_spec {
      image = "mcr.microsoft.com/playwright/mcp:latest"
      env = var.env

      args = [
        "--headless",
        "--browser", "chromium",
        "--no-sandbox",
        "--port", "8931",
        "--host", "0.0.0.0",
        "--allowed-hosts", "*",
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = "mcp-playwright-nfs"
        target = var.nfs.target

        volume_options {
          driver_name    = "local"
          driver_options = var.nfs.driver_options
          no_copy        = false
        }
      }
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
      target_port    = 8931
      published_port = 18211
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
