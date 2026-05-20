resource "docker_network" "telegraf_docker_metrics" {
  name   = "telegraf-docker-metrics"
  driver = "overlay"
}

resource "docker_config" "telegraf" {
  name = "telegraf-docker-metrics-${local.telegraf_config_hash}"
  data = filebase64("${path.module}/telegraf.conf")

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "telegraf_docker_metrics" {
  name = "telegraf-docker-metrics"

  task_spec {
    force_update = local.telegraf_force_update

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
      name        = docker_network.telegraf_docker_metrics.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "telegraf:1.38.4@sha256:fb0a95f7a42958b1e7219faf075552795f7e043432a28c54baf070442b6259ee"
      user  = "0:0"
      command = [
        "telegraf",
      ]

      args = [
        "--config",
        "/etc/telegraf/telegraf.conf",
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target    = "/var/run/docker.sock"
        source    = "/var/run/docker.sock"
        type      = "bind"
        read_only = false
      }

      configs {
        config_id   = docker_config.telegraf.id
        config_name = docker_config.telegraf.name
        file_name   = "/etc/telegraf/telegraf.conf"
      }
    }
  }

  mode {
    global = true
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = 9273
      published_port = 19273
      publish_mode   = "host"
    }
  }
}
