resource "docker_network" "cloud_image_repository" {
  name   = "cloud-image-repository"
  driver = "overlay"
}

resource "docker_volume" "cloud_image_repository_data" {
  name   = "cloud-image-repository-data"
  driver = "local"
}

resource "docker_service" "cloud_image_repository" {
  name = "cloud-image-repository"

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
      name    = docker_network.cloud_image_repository.id
      aliases = ["cloud-image-repository"]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/cloud-image-repository:0.0.1"

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.cloud_image_repository_data.name
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
      target_port    = 8080
      published_port = 18088
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
