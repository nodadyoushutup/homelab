# main.tf
# Overlay network, data/letsencrypt volumes, and nginx-proxy-manager Swarm service.

data "docker_network" "nginx_proxy_manager_mysql" {
  name = local.mysql_network_name
}

resource "docker_network" "nginx_proxy_manager" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "nginx_proxy_manager_data" {
  name   = local.data_volume_name
  driver = "local"
}

resource "docker_volume" "nginx_proxy_manager_letsencrypt" {
  name   = local.letsencrypt_volume_name
  driver = "local"
}

resource "docker_service" "nginx_proxy_manager" {
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
      name    = docker_network.nginx_proxy_manager.id
      aliases = [local.network_alias]
    }

    networks_advanced {
      name    = data.docker_network.nginx_proxy_manager_mysql.id
      aliases = []
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "jc21/nginx-proxy-manager:2.12.6"
      env   = local.env

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.nginx_proxy_manager_data.name
        target = local.data_mount
      }

      mounts {
        type   = "volume"
        source = docker_volume.nginx_proxy_manager_letsencrypt.name
        target = local.letsencrypt_mount
      }
    }
  }

  endpoint_spec {
    ports {
      target_port    = local.http_port
      published_port = local.http_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = local.https_port
      published_port = local.https_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = local.admin_port
      published_port = local.admin_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
