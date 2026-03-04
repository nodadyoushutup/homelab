locals {
  grafana_ini_hash         = substr(filemd5("${path.module}/grafana.ini"), 0, 12)
  grafana_ini_force_update = parseint(substr(local.grafana_ini_hash, 0, 8), 16)
}

data "docker_network" "external" {
  for_each = "prometheus"
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
  name = "grafana-ini-${local.grafana_ini_hash}"
  data = filebase64("${path.module}/grafana.ini")

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "grafana" {
  name = "grafana"

  task_spec {
    force_update = local.grafana_ini_force_update

    placement {
      constraints = ["node.labels.role==swarm-cp-0"]
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.grafana.id
      aliases = ["grafana"]
    }

    container_spec {
      image = "grafana/grafana:12.3.1@sha256:2175aaa91c96733d86d31cf270d5310b278654b03f5718c59de12a865380a31f"
      env   = var.env

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
}
