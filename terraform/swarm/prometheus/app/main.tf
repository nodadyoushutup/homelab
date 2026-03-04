locals {
  prometheus_config_hash  = substr(filemd5("${path.module}/prometheus.yaml"), 0, 12)
  prometheus_force_update = parseint(substr(local.prometheus_config_hash, 0, 8), 16)
}

data "docker_network" "victoriametrics" {
  name = "victoriametrics"
}

resource "docker_network" "prometheus" {
  name   = "prometheus"
  driver = "overlay"
}

resource "docker_volume" "prometheus_data" {
  name = "prometheus-data"
}

resource "docker_config" "prometheus" {
  name = "prometheus-${local.prometheus_config_hash}"
  data = filebase64("${path.module}/prometheus.yaml")

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "prometheus" {
  name = "prometheus"

  task_spec {
    force_update = local.prometheus_force_update

    placement {
      constraints = ["node.labels.role==swarm-cp-0"]
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name        = docker_network.prometheus.id
      aliases     = []
      driver_opts = []
    }

    networks_advanced {
      name        = data.docker_network.victoriametrics.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "prom/prometheus:v3.9.1@sha256:1f0f50f06acaceb0f5670d2c8a658a599affe7b0d8e78b898c1035653849a702"

      args = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--storage.tsdb.retention.time=15d",
        "--web.enable-lifecycle",
        "--web.enable-admin-api",
      ]

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/prometheus"
        source = docker_volume.prometheus_data.name
        type   = "volume"
      }

      configs {
        config_id   = docker_config.prometheus.id
        config_name = docker_config.prometheus.name
        file_name   = "/etc/prometheus/prometheus.yml"
      }

      healthcheck {
        test         = ["CMD", "wget", "--spider", "--quiet", "http://localhost:9090/-/healthy"]
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
      target_port    = 9090
      published_port = 9090
      publish_mode   = "ingress"
    }
  }
}
