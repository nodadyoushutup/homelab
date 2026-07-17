# main.tf
# Overlay network, data volume, and replicated cloud-image-repository Swarm service.

resource "docker_network" "cloud_image_repository" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "cloud_image_repository_data" {
  name   = local.volume_name
  driver = "local"
}

resource "docker_service" "cloud_image_repository" {
  name = local.service_name

  task_spec {
    dynamic "placement" {
      for_each = local.placement == null ? [] : [local.placement]

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
      name    = docker_network.cloud_image_repository.id
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/nodadyoushutup/cloud-image-repository:0.0.2"

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.cloud_image_repository_data.name
        target = local.data_mount
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
      target_port    = local.target_port
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
