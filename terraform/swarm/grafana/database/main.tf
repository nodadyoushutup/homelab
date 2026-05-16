resource "docker_network" "grafana_database" {
  name   = "grafana-database"
  driver = "overlay"
}

resource "docker_volume" "grafana_database" {
  name   = "grafana-database"
  driver = "local"
}

resource "docker_service" "grafana_database" {
  name = "grafana-database"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.grafana_database.id
      aliases = ["grafana"]
    }

    container_spec {
      image = "postgres:18.3"
      env = {
        POSTGRES_PASSWORD = var.env.POSTGRES_PASSWORD
        POSTGRES_USER     = var.env.POSTGRES_USER
        POSTGRES_DB       = var.env.POSTGRES_DB
      }

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/var/lib/postgresql"
        source = docker_volume.grafana_database.name
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
      target_port    = 5432
      published_port = 5432
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
