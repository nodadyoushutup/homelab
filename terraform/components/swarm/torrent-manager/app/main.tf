resource "docker_network" "torrent_manager" {
  name   = "torrent-manager"
  driver = "overlay"
}

resource "docker_volume" "torrent_manager_data" {
  name = "torrent-manager-data"
}

resource "docker_config" "torrent_manager" {
  name = "torrent-manager-config-${substr(sha256(file(var.config_host_path)), 0, 8)}"
  data = filebase64(var.config_host_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "torrent_manager" {
  name = "torrent-manager"

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
      name    = docker_network.torrent_manager.id
      aliases = ["torrent-manager"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/torrent-manager:0.0.4"

      env = {
        TORRENT_MANAGER_CONFIG_PATH = "/etc/torrent-manager/config.yaml"
      }

      dns_config {
        nameservers = var.dns_nameservers
      }

      configs {
        config_id   = docker_config.torrent_manager.id
        config_name = docker_config.torrent_manager.name
        file_name   = "/etc/torrent-manager/config.yaml"
        file_mode   = 0444
      }

      mounts {
        target = "/data"
        source = docker_volume.torrent_manager_data.name
        type   = "volume"
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
      target_port    = 8080
      published_port = 9030
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
