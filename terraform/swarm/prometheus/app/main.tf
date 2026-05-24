data "docker_network" "victoriametrics" {
  name = "victoriametrics-net"
}

resource "docker_network" "prometheus" {
  name   = "prometheus"
  driver = "overlay"
}

resource "docker_volume" "prometheus_data" {
  name = "prometheus-data"
}

resource "docker_config" "prometheus" {
  name = "prometheus-${local.config_hash}"
  data = filebase64(var.config_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "prometheus" {
  name = "prometheus"

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
      name    = docker_network.prometheus.id
      aliases = ["prometheus"]
    }

    networks_advanced {
      name    = data.docker_network.victoriametrics.id
      aliases = []
    }

    container_spec {
      image = "prom/prometheus:v3.9.1@sha256:1f0f50f06acaceb0f5670d2c8a658a599affe7b0d8e78b898c1035653849a702"

      args = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--storage.tsdb.retention.time=1h",
        "--web.enable-lifecycle",
        "--web.enable-admin-api",
      ]

      dns_config {
        nameservers = var.dns_nameservers
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
      target_port    = 9090
      published_port = 9090
      publish_mode   = "ingress"
    }
  }
}
