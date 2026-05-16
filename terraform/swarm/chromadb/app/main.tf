resource "docker_network" "chromadb" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "chromadb_data" {
  name = local.chromadb_data_volume
}

resource "docker_service" "chromadb" {
  name = local.service_name

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
      aliases = [local.service_name]
    }

    container_spec {
      image = local.chromadb_image

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
      target_port    = local.internal_port
      published_port = local.chromadb_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
