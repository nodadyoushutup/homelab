resource "docker_network" "nginx_proxy_manager" {
  name   = "nginx-proxy-manager"
  driver = "overlay"
}

resource "docker_volume" "nginx_proxy_manager_data" {
  name   = "nginx-proxy-manager-data"
  driver = "local"
}

resource "docker_volume" "nginx_proxy_manager_letsencrypt" {
  name   = "nginx-proxy-manager-letsencrypt"
  driver = "local"
}

resource "docker_service" "nginx_proxy_manager" {
  name = "nginx-proxy-manager"

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
      name    = docker_network.nginx_proxy_manager.id
      aliases = ["nginx-proxy-manager", "npm"]
    }

    container_spec {
      image = "jc21/nginx-proxy-manager:2.13.6@sha256:669be1a294d4491b842f542d238ea1d4bca8f76fbedd7d99b45b24cd5a8cff99"
      env = merge(
        {
          INITIAL_ADMIN_EMAIL = coalesce(
            try(var.provider_config.nginx_proxy_manager.username, null),
            "admin@example.com",
          )
          INITIAL_ADMIN_PASSWORD = coalesce(
            try(var.provider_config.nginx_proxy_manager.password, null),
            "changeme",
          )
        },
        var.env == null ? {} : var.env,
      )

      dynamic "dns_config" {
        for_each = var.dns_nameservers == null ? [] : [var.dns_nameservers]

        content {
          nameservers = dns_config.value
        }
      }

      mounts {
        type   = "volume"
        source = docker_volume.nginx_proxy_manager_data.name
        target = "/data"
      }

      mounts {
        type   = "volume"
        source = docker_volume.nginx_proxy_manager_letsencrypt.name
        target = "/etc/letsencrypt"
      }

      healthcheck {
        test         = ["CMD", "/usr/bin/check-health"]
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
      target_port    = 80
      published_port = 80
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 443
      published_port = 443
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 81
      published_port = 81
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
