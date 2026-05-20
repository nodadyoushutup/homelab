resource "docker_network" "cloud_image_repository" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "cloud_image_repository_data" {
  name   = local.data_volume_name
  driver = "local"
}

resource "docker_service" "cloud_image_repository" {
  name = local.service_name

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
      name    = docker_network.cloud_image_repository.id
      aliases = [local.service_name]
    }

    container_spec {
      image = "ghcr.io/nodadyoushutup/cloud-image-repository:0.0.1"

      env = {
        CLOUD_IMAGE_REPOSITORY_DATA_ROOT = local.data_mount_target
        CLOUD_IMAGE_REPOSITORY_UI_ROOT   = local.ui_mount_target
        CLOUD_IMAGE_REPOSITORY_PORT      = tostring(local.internal_port)
      }

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.cloud_image_repository_data.name
        target = local.data_mount_target
      }

      healthcheck {
        test         = ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/', timeout=5).read(1)"]
        interval     = "15s"
        timeout      = "5s"
        retries      = 5
        start_period = "20s"
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
      target_port    = local.internal_port
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
