resource "docker_network" "zot" {
  name   = var.network_name
  driver = "overlay"
}

resource "docker_volume" "zot_data" {
  name   = var.volume_name
  driver = "local"
}

resource "docker_config" "zot" {
  name = "zot-config-${local.config_hash}"
  data = base64encode(local.zot_config_json)

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
      image = var.image

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.zot_data.name
        target = "/var/lib/registry"
      }

      dynamic "mounts" {
        for_each = var.enable_auth ? [var.htpasswd_file_path] : []

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
      target_port    = var.http_port
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }

  lifecycle {
    precondition {
      condition     = !var.enable_auth || trimspace(var.htpasswd_file_path) != ""
      error_message = "enable_auth requires htpasswd_file_path pointing at a host htpasswd file."
    }
  }
}
