data "docker_network" "prometheus" {
  name = "prometheus"
}

resource "docker_network" "prometheus_pve_exporter" {
  name   = "prometheus-pve-exporter"
  driver = "overlay"
}

resource "docker_service" "prometheus_pve_exporter" {
  name = local.service_name

  dynamic "auth" {
    for_each = local.docker_service_pull_auth_map

    content {
      server_address = auth.value.server_address
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
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
      image = var.image_reference
      env   = local.exporter_env
      args  = local.exporter_args

      dns_config {
        nameservers = var.dns_nameservers
      }

      healthcheck {
        test         = ["CMD", "wget", "--spider", "--quiet", "http://127.0.0.1:${local.internal_port}/metrics"]
        interval     = "30s"
        timeout      = "10s"
        retries      = 6
        start_period = "60s"
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
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "host"
    }
  }
}
