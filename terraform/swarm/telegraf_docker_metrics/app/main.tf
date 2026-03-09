locals {
  telegraf_config_hash  = substr(filemd5("${path.module}/telegraf.conf"), 0, 12)
  telegraf_force_update = parseint(substr(local.telegraf_config_hash, 0, 8), 16)
}

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

    placement {
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name        = docker_network.telegraf_docker_metrics.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "telegraf:1.36.3@sha256:532feb6341c2eb835eac808160f3011f3e5b0f87cb05e53797e6c98e107708dc"
      user  = "0:0"
      command = [
        "telegraf",
      ]

      args = [
        "--config",
        "/etc/telegraf/telegraf.conf",
      ]

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
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
