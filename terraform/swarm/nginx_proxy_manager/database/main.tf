resource "docker_network" "nginx_proxy_manager_mysql" {
  # Keep network name distinct from service name. Using identical names causes
  # Swarm DNS lookups for the service to return NXDOMAIN on this network.
  name   = "nginx-proxy-manager-mysql"
  driver = "overlay"
}

resource "docker_volume" "mysql" {
  name   = "mysql-data"
  driver = "local"
}

resource "docker_service" "mysql" {
  name = "mysql"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.nginx_proxy_manager_mysql.id
      aliases = ["mysql"]
    }

    container_spec {
      image = "jc21/mariadb-aria:10.11.5"
      env = {
        MYSQL_DATABASE       = var.env.MYSQL_DATABASE
        MYSQL_USER           = var.env.MYSQL_USER
        MYSQL_PASSWORD       = var.env.MYSQL_PASSWORD
        MARIADB_AUTO_UPGRADE = var.env.MARIADB_AUTO_UPGRADE
      }

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/var/lib/mysql"
        source = docker_volume.mysql.name
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
