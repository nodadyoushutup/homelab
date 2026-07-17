# main.tf
# Overlay network and mcp-playwright Swarm service (NFS-backed browser profile volume).

resource "docker_network" "mcp_playwright" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_playwright" {
  name = local.service_name

  task_spec {
    dynamic "placement" {
      for_each = local.placement == null ? [] : [local.placement]

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
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "mcr.microsoft.com/playwright/mcp:v0.0.78"
      env   = local.env

      args = local.args

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = local.nfs_volume_source
        target = local.nfs.target

        volume_options {
          driver_name    = "local"
          driver_options = local.nfs.driver_options
          no_copy        = false
        }
      }
    }
  }

  mode {
    replicated {
      replicas = local.replicas
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = local.service_port.target_port
      published_port = local.service_port.published_port
      protocol       = local.service_port.protocol
      publish_mode   = local.service_port.publish_mode
    }
  }
}
