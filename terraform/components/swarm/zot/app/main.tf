resource "docker_network" "zot" {
  name   = "zot"
  driver = "overlay"
}

resource "docker_volume" "zot_data" {
  name   = "zot-data"
  driver = "local"
}

resource "docker_config" "zot" {
  name = "zot-config-${local.config_hash}"
  data = base64encode(local.zot_config_raw)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "zot" {
  name = "zot"

  task_spec {
    force_update = local.force_update

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
      name    = docker_network.zot.id
      aliases = ["zot"]
    }

    container_spec {
      image = "ghcr.io/project-zot/zot:v2.1.15@sha256:376cb38a335bab89571af306eff481547212746aff11828043c22f32637fe17b"

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.zot_data.name
        target = "/var/lib/registry"
      }

      dynamic "mounts" {
        for_each = local.auth_enabled ? [var.htpasswd_path] : []

        content {
          type      = "bind"
          source    = mounts.value
          target    = "/etc/zot/htpasswd"
          read_only = true
        }
      }

      configs {
        config_id   = docker_config.zot.id
        config_name = docker_config.zot.name
        file_name   = "/etc/zot/config.json"
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
      published_port = 35081
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
