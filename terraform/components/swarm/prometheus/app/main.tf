# main.tf
# Overlay network, data volume, config, and Prometheus Swarm service wired to VictoriaMetrics.

data "docker_network" "victoriametrics" {
  name = local.victoriametrics_network_name
}

resource "docker_network" "prometheus" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "prometheus_data" {
  name = local.volume_name
}

resource "docker_config" "prometheus" {
  name = local.config_name
  data = filebase64(local.config_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "prometheus" {
  name = local.service_name

  task_spec {
    force_update = local.force_update

    dynamic "placement" {
      for_each = local.placement == null ? [] : [local.placement]

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
      aliases = [local.network_alias]
    }

    networks_advanced {
      name    = data.docker_network.victoriametrics.id
      aliases = []
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "prom/prometheus:v3.9.1"
      args  = local.args

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.data_mount
        source = docker_volume.prometheus_data.name
        type   = "volume"
      }

      configs {
        config_id   = docker_config.prometheus.id
        config_name = docker_config.prometheus.name
        file_name   = local.config_mount
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
      target_port    = local.target_port
      published_port = local.published_port
      publish_mode   = "ingress"
    }
  }
}
