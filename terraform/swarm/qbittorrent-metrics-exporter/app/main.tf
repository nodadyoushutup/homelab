data "docker_network" "prometheus" {
  name = "prometheus"
}

resource "docker_network" "qbittorrent_exporter" {
  name   = "qbittorrent-exporter"
  driver = "overlay"
}

resource "docker_service" "qbittorrent_exporter" {
  for_each = local.qbittorrent_hosts

  name = "${local.service_name_prefix}-${each.key}"

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
      name    = docker_network.qbittorrent_exporter.id
      aliases = ["${local.service_name_prefix}-${each.key}"]
    }

    networks_advanced {
      name    = data.docker_network.prometheus.id
      aliases = []
    }

    container_spec {
      image = var.image_reference
      env   = local.per_instance_env[each.key]

      dns_config {
        nameservers = var.dns_nameservers
      }

      healthcheck {
        test         = ["CMD", "wget", "--spider", "--quiet", "http://127.0.0.1:${local.internal_port}/metrics"]
        interval     = "30s"
        timeout      = "10s"
        retries      = 10
        start_period = "120s"
      }
    }

    restart_policy {
      condition    = "any"
      delay        = "30s"
      max_attempts = 0
      window       = "0s"
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
      target_port    = local.internal_port
      published_port = local.instance_ports[each.key]
      protocol       = "tcp"
      publish_mode   = "host"
    }
  }
}
