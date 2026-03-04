resource "docker_network" "docker_volume_backup" {
  name   = "docker-volume-backup"
  driver = "overlay"
}

resource "docker_service" "docker_volume_backup" {
  name = "docker-volume-backup"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.docker_volume_backup.id
      aliases = ["docker-volume-backup"]
    }

    container_spec {
      image = "offen/docker-volume-backup:v2.47.2"
      env   = var.env

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      dynamic "mounts" {
        for_each = var.backup_mounts
        content {
          target    = mounts.value.target
          source    = mounts.value.source
          type      = mounts.value.type
          read_only = mounts.value.read_only
        }
      }

      mounts {
        target    = "/var/run/docker.sock"
        source    = "/var/run/docker.sock"
        type      = "bind"
        read_only = true
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }
}
