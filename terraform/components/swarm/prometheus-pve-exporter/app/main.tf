# main.tf
# Overlay network and prometheus-pve-exporter Swarm service wired to Prometheus.

data "docker_network" "prometheus" {
  name = local.prometheus_network_name
}

resource "docker_network" "prometheus_pve_exporter" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "prometheus_pve_exporter" {
  name = local.service_name

  task_spec {
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
      name    = docker_network.prometheus_pve_exporter.id
      aliases = [local.service_name]
    }

    networks_advanced {
      name = data.docker_network.prometheus.id
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "prompve/prometheus-pve-exporter:3.9.0"
      env   = local.exporter_env
      args  = local.exporter_args

      dns_config {
        nameservers = local.dns_nameservers
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
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "host"
    }
  }
}
