resource "docker_network" "victoriametrics" {
  name   = "victoriametrics"
  driver = "overlay"
}

resource "docker_volume" "victoriametrics_data" {
  name   = "victoriametrics-data"
  driver = "local"
}

resource "docker_service" "victoriametrics" {
  name = "victoriametrics"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-wk-0"]
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.victoriametrics.id
      aliases = ["victoriametrics"]
    }

    container_spec {
      image = "victoriametrics/victoria-metrics:v1.137.0"

      args = [
        "-storageDataPath=/victoria-metrics-data",
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/victoria-metrics-data"
        source = docker_volume.victoriametrics_data.name
        type   = "volume"
      }

      healthcheck {
        test         = ["CMD", "wget", "--spider", "--quiet", "http://127.0.0.1:8428/health"]
        interval     = "10s"
        timeout      = "5s"
        retries      = 6
        start_period = "30s"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  endpoint_spec {
    ports {
      target_port    = 8428
      published_port = 8428
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
