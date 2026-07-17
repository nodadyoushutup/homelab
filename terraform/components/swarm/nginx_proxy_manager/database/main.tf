# main.tf
# Overlay network, data volume, and replicated nginx-proxy-manager-mysql Swarm service.

resource "docker_network" "nginx_proxy_manager_mysql" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "nginx_proxy_manager_mysql_data" {
  name   = local.volume_name
  driver = "local"
}

resource "docker_service" "nginx_proxy_manager_mysql" {
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
      name    = docker_network.nginx_proxy_manager_mysql.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "jc21/mariadb-aria:10.11.5"
      env   = local.env

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.data_mount
        source = docker_volume.nginx_proxy_manager_mysql_data.name
        type   = "volume"
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
      target_port    = local.mysql_port
      published_port = local.mysql_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
