locals {
  admin_password   = tostring(var.provider_config.grafana.password)
  grafana_ini_path = "${path.module}/grafana.ini"
  # Order matches Swarm's platform reporting (aarch64 then arm64) to prevent perpetual plan diffs.
  allowed_platforms = [
    {
      os           = "linux"
      architecture = "aarch64"
    },
    {
      os           = "linux"
      architecture = "arm64"
    }
  ]
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

resource "terraform_data" "platforms" {
  input = local.allowed_platforms
}

resource "docker_secret" "grafana_admin_password" {
  name = "grafana-admin-password"
  data = base64encode(local.admin_password)
}

resource "docker_config" "grafana_ini" {
  name = format("grafana-ini-%s", substr(sha256(file(local.grafana_ini_path)), 0, 12))
  data = filebase64(local.grafana_ini_path)
}

resource "docker_service" "grafana" {
  name = "grafana"
  depends_on = [terraform_data.platforms]

  labels {
    label = "com.docker.stack.namespace"
    value = "grafana"
  }

  labels {
    label = "com.docker.service"
    value = "grafana"
  }

  task_spec {
    placement {
      dynamic "platforms" {
        for_each = local.allowed_platforms

        content {
          os           = platforms.value.os
          architecture = platforms.value.architecture
        }
      }

      constraints = ["node.labels.role==swarm-cp-0"]
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
      image = "grafana/grafana:12.3.0@sha256:fb238b17317d9dc532b5dd9008862e3a5c1a248da2c27f420446d3e068a79c46"
      env = {
        GF_SECURITY_ADMIN_USER           = "admin"
        GF_SECURITY_ADMIN_PASSWORD__FILE = "/run/secrets/grafana-admin-password"
        GF_SERVER_HTTP_PORT              = "3000"
        GF_SERVER_ROOT_URL               = "https://grafana.nodadyoushutup.com"
        GF_USERS_ALLOW_SIGN_UP           = "false"
        GF_SERVER_DOMAIN                 = "grafana.nodadyoushutup.com"
        GF_INSTALL_PLUGINS               = "grafana-clock-panel,grafana-piechart-panel"
      }

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/var/lib/grafana"
        source = docker_volume.grafana_data.name
        type   = "volume"
      }

      secrets {
        secret_id   = docker_secret.grafana_admin_password.id
        secret_name = docker_secret.grafana_admin_password.name
        file_name   = "/run/secrets/grafana-admin-password"
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
    ignore_changes = [
      task_spec[0].placement[0].platforms,
    ]
    replace_triggered_by = [
      docker_secret.grafana_admin_password,
      docker_config.grafana_ini,
      terraform_data.platforms,
    ]
  }
}
