# main.tf
# Overlay network, data volume, config, and zot registry Swarm service.

resource "docker_network" "zot" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "zot_data" {
  name   = local.volume_name
  driver = "local"
}

resource "docker_config" "zot" {
  name = local.config_name
  data = base64encode(local.zot_config_raw)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "zot" {
  name = local.service_name

  task_spec {
    force_update = local.force_update

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
      name    = docker_network.zot.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/project-zot/zot:v2.1.15"

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.zot_data.name
        target = local.data_mount
      }

      dynamic "mounts" {
        for_each = local.auth_enabled ? [local.htpasswd_path] : []

        content {
          type      = "bind"
          source    = mounts.value
          target    = local.htpasswd_mount
          read_only = true
        }
      }

      configs {
        config_id   = docker_config.zot.id
        config_name = docker_config.zot.name
        file_name   = local.config_mount
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = tonumber(local.zot_config.http.port)
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
