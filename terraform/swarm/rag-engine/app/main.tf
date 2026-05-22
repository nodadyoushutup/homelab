data "docker_network" "chromadb" {
  name = "chromadb"
}

resource "docker_network" "rag_engine" {
  name   = "rag-engine"
  driver = "overlay"
}

resource "docker_service" "rag_engine" {
  name = "rag-engine"

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
      image = "harbor.nodadyoushutup.com/homelab/rag-engine:0.0.7"
      env   = var.env

      dns_config {
        nameservers = var.dns_nameservers
      }

      dynamic "mounts" {
        for_each = (
          trimspace(var.swarm_nfs_code_device) != "" &&
          trimspace(var.swarm_nfs_config_device) != "" &&
          trimspace(var.swarm_nfs_volume_type) != "" &&
          trimspace(var.swarm_nfs_volume_o_rw) != "" &&
          trimspace(var.swarm_nfs_volume_o_ro) != ""
        ) ? [1] : []

        content {
          type      = "volume"
          source    = "rag-engine-mnt-eapp-code"
          target    = trimspace(element(split(":", trimspace(var.swarm_nfs_code_device)), length(split(":", trimspace(var.swarm_nfs_code_device))) - 1))
          read_only = true

          volume_options {
            driver_name = "local"
            driver_options = {
              type   = trimspace(var.swarm_nfs_volume_type)
              o      = trimspace(var.swarm_nfs_volume_o_ro)
              device = trimspace(var.swarm_nfs_code_device)
            }
            no_copy = false
          }
        }
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
      target_port    = 8080
      published_port = 9015
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
