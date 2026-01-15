resource "docker_network" "prometheus" {
  name   = "prometheus"
  driver = "overlay"
}

resource "docker_volume" "prometheus_data" {
  name = "prometheus-data"
}

resource "docker_config" "prometheus" {
  name = format(
    "prometheus-%s.yml",
    substr(
      sha256(
        yamlencode({
          global = {
            scrape_interval     = "15s"
            evaluation_interval = "15s"
          }
          scrape_configs = [
            {
              job_name     = "node_exporter"
              metrics_path = "/metrics"
              static_configs = [
                {
                  targets = var.targets == null ? [] : var.targets
                }
              ]
            }
          ]
        })
      ),
      0,
      12
    )
  )
  data = base64encode(
    yamlencode({
      global = {
        scrape_interval     = "15s"
        evaluation_interval = "15s"
      }
      scrape_configs = [
        {
          job_name     = "node_exporter"
          metrics_path = "/metrics"
          static_configs = [
            {
              targets = var.targets == null ? [] : var.targets
            }
          ]
        }
      ]
    })
  )
}

resource "docker_service" "prometheus" {
  name = "prometheus"

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
      name        = docker_network.prometheus.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "prom/prometheus:v3.7.3@sha256:49214755b6153f90a597adcbff0252cc61069f8ab69ce8411285cd4a560e8038"

      args = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--storage.tsdb.retention.time=15d",
        "--web.enable-lifecycle",
      ]

      dynamic "dns_config" {
        for_each = var.dns_nameservers == null ? [] : [var.dns_nameservers]

        content {
          nameservers = dns_config.value
        }
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

  lifecycle {
    replace_triggered_by = [
      docker_config.prometheus,
    ]
  }
}
