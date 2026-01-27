locals {
  grafana_ini_path = "${path.module}/grafana.ini"
}

data "docker_network" "external" {
  for_each = toset(["prometheus"])
  name     = each.value
}

resource "docker_network" "grafana" {
  name   = "grafana"
  driver = "overlay"
}

resource "docker_volume" "grafana_data" {
  name   = "grafana-data"
  driver = "local"
}

resource "docker_config" "grafana_ini" {
  name = format("grafana-ini-%s", substr(sha256(file(local.grafana_ini_path)), 0, 12))
  data = filebase64(local.grafana_ini_path)
}

resource "docker_service" "grafana" {
  name = "grafana"

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
      name    = docker_network.grafana.id
      aliases = ["grafana"]
    }

    dynamic "networks_advanced" {
      for_each = data.docker_network.external

      content {
        name    = networks_advanced.value.id
        aliases = []
      }
    }

    container_spec {
      image = "grafana/grafana:12.3.2@sha256:ba93c9d192e58b23e064c7f501d453426ccf4a85065bf25b705ab1e98602bfb1"
      env = var.env == null ? {} : var.env

      dynamic "dns_config" {
        for_each = var.dns_nameservers == null ? [] : [var.dns_nameservers]

        content {
          nameservers = dns_config.value
        }
      }

      mounts {
        target = "/var/lib/grafana"
        source = docker_volume.grafana_data.name
        type   = "volume"
      }

      configs {
        config_id   = docker_config.grafana_ini.id
        config_name = docker_config.grafana_ini.name
        file_name   = "/etc/grafana/grafana.ini"
      }

      healthcheck {
        test         = ["CMD", "wget", "--spider", "--quiet", "http://localhost:3000/api/health"]
        interval     = "15s"
        timeout      = "5s"
        retries      = 5
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
      target_port    = 3000
      published_port = 3000
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }

  lifecycle {
    replace_triggered_by = [
      docker_config.grafana_ini,
    ]
  }
}
