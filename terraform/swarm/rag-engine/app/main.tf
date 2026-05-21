data "docker_network" "chromadb" {
  name = "chromadb"
}

resource "docker_network" "rag_engine" {
  name   = "rag-engine"
  driver = "overlay"
}

resource "docker_service" "rag_engine" {
  name = "rag-engine"

  dynamic "auth" {
    for_each = local.docker_service_pull_auth_map

    content {
      server_address = auth.value.server_address
      username       = auth.value.username
      password       = auth.value.password
    }
  }

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
      name    = docker_network.rag_engine.id
      aliases = ["rag-engine"]
    }

    networks_advanced {
      name    = data.docker_network.chromadb.id
      aliases = []
    }

    container_spec {
      image = var.image_reference
      env   = local.effective_env

      dns_config {
        nameservers = var.dns_nameservers
      }

      dynamic "mounts" {
        for_each = local.swarm_nfs_code_mounts

        content {
          type      = mounts.value.type
          source    = mounts.value.source
          target    = mounts.value.target
          read_only = mounts.value.read_only

          volume_options {
            driver_name    = mounts.value.volume_options.driver_name
            driver_options = mounts.value.volume_options.driver_options
            no_copy        = mounts.value.volume_options.no_copy
          }
        }
      }
    }

    restart_policy {
      condition    = "on-failure"
      delay        = "10s"
      max_attempts = 3
      window       = "2m"
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
      target_port    = 8080
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
