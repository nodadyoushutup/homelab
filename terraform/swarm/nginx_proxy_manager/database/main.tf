resource "docker_network" "nginx_proxy_manager_mysql" {
  name   = "nginx-proxy-manager-mysql"
  driver = "overlay"
}

resource "docker_volume" "nginx_proxy_manager_mysql_data" {
  name   = "nginx-proxy-manager-mysql-data"
  driver = "local"
}

resource "docker_service" "nginx_proxy_manager_mysql" {
  name = "nginx-proxy-manager-mysql"

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
      name    = docker_network.nginx_proxy_manager_mysql.id
      aliases = ["mysql"]
    }

    container_spec {
      image = "jc21/mariadb-aria:10.11.5"
      env   = var.env

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/var/lib/mysql"
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
      target_port    = 3306
      published_port = 3306
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
