# main.tf
# Overlay network and replicated cloud-image-repository Swarm service.
# There is no persistent local data volume: the served /data directory is an NFS
# mount of data/packer, so Packer output and REST uploads share one backing store.

resource "docker_network" "cloud_image_repository" {
  name   = local.network_name
  driver = "overlay"
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
      image = "ghcr.io/nodadyoushutup/cloud-image-repository:0.0.10"

      dns_config {
        nameservers = local.dns_nameservers
      }

      # NFS-backed volume (no local data): serves data/packer directly so a local
      # Packer run that writes there is published without a REST upload.
      mounts {
        type   = "volume"
        source = local.volume_name
        target = local.data_mount

        volume_options {
          driver_name    = "local"
          driver_options = local.nfs_driver_options
          no_copy        = true
        }
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
