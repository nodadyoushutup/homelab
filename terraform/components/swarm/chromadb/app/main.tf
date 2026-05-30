resource "docker_network" "chromadb" {
  name   = "chromadb"
  driver = "overlay"
}

resource "docker_volume" "chromadb_data" {
  name   = "chromadb-data"
  driver = "local"
}

resource "docker_service" "chromadb" {
  name = "chromadb"

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
      name    = docker_network.chromadb.id
      aliases = ["chromadb"]
    }

    container_spec {
      image = "chromadb/chroma:1.5.9"

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.chromadb_data.name
        target = "/data"
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

  endpoint_spec {
    ports {
      target_port    = 8000
      published_port = 8000
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
