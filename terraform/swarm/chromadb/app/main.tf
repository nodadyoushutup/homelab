resource "docker_network" "chromadb" {
  name   = "chromadb"
  driver = "overlay"
}

resource "docker_volume" "chromadb_data" {
  name = "chromadb-data"
}

resource "docker_service" "chromadb" {
  name = "chromadb"

  task_spec {
    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    networks_advanced {
      name    = docker_network.chromadb.id
      aliases = ["chromadb"]
    }

    container_spec {
      # Pin matches chroma-core/chroma GitHub release (not Docker "latest"); bump when upgrading Chroma.
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
      replicas = var.replicas
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
