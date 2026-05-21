resource "docker_network" "graylog_mongodb" {
  name   = "graylog-mongodb"
  driver = "overlay"
}

resource "docker_volume" "graylog_mongodb_data" {
  name = "graylog-mongodb-data"
}

resource "docker_volume" "graylog_mongodb_config" {
  name = "graylog-mongodb-config"
}

resource "docker_service" "graylog_mongodb" {
  name = "graylog-mongodb"

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
      name    = docker_network.graylog_mongodb.id
      aliases = ["mongodb"]
    }

    container_spec {
      image = "mongo:7.0.21@sha256:3d715950d83061ff2fbc910d12d3703212538cacf6b3003e3736fa5c7f51a2e1"

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/data/db"
        source = docker_volume.graylog_mongodb_data.name
        type   = "volume"
      }

      mounts {
        target = "/data/configdb"
        source = docker_volume.graylog_mongodb_config.name
        type   = "volume"
      }

      healthcheck {
        test         = ["CMD", "mongosh", "--quiet", "--eval", "db.adminCommand('ping').ok"]
        interval     = "15s"
        timeout      = "5s"
        retries      = 10
        start_period = "30s"
      }
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
}
