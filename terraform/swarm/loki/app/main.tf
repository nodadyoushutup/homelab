locals {
  loki_config_hash  = substr(filemd5(var.loki_config_path), 0, 12)
  loki_force_update = parseint(substr(local.loki_config_hash, 0, 8), 16)
}

resource "docker_network" "loki" {
  name   = "loki"
  driver = "overlay"
}

resource "docker_volume" "loki_data" {
  name = "loki-data"
}

resource "docker_config" "loki" {
  name = "loki-config-${local.loki_config_hash}"
  data = filebase64(var.loki_config_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "loki" {
  name = "loki"

  task_spec {
    force_update = local.loki_force_update

    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name        = docker_network.loki.id
      aliases     = ["loki"]
      driver_opts = []
    }

    container_spec {
      image = "grafana/loki:3.7.2@sha256:191d4fdfb7264f16989f0a57f320872620a5a7c2ceeec6229212c4190ec49b86"

      args = [
        "-config.file=/etc/loki/config.yaml",
      ]

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/loki"
        source = docker_volume.loki_data.name
        type   = "volume"
      }

      configs {
        config_id   = docker_config.loki.id
        config_name = docker_config.loki.name
        file_name   = "/etc/loki/config.yaml"
      }

      healthcheck {
        test = [
          "CMD-SHELL",
          "wget -q -O- http://127.0.0.1:3100/ready | grep -q 'ready'",
        ]
        interval     = "15s"
        timeout      = "5s"
        retries      = 10
        start_period = "45s"
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
      target_port    = 3100
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
