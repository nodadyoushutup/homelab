resource "docker_network" "cadvisor" {
  name   = "cadvisor"
  driver = "overlay"
}

resource "docker_service" "cadvisor" {
  name = "cadvisor"

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
      name    = docker_network.cadvisor.id
      aliases = ["cadvisor"]
    }

    container_spec {
      image = "ghcr.io/google/cadvisor:v0.57.0"

      args = [
        "--docker=unix:///var/run/docker.sock",
        "--docker_only=true",
        "--store_container_labels=false",
        "--whitelisted_container_labels=com.docker.swarm.service.name,com.docker.swarm.task.name,com.docker.swarm.node.id",
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target    = "/rootfs"
        source    = "/"
        type      = "bind"
        read_only = true
      }

      mounts {
        target = "/var/run/docker.sock"
        source = "/var/run/docker.sock"
        type   = "bind"
      }

      mounts {
        target    = "/var/run"
        source    = "/var/run"
        type      = "bind"
        read_only = true
      }

      mounts {
        target    = "/sys"
        source    = "/sys"
        type      = "bind"
        read_only = true
      }

      mounts {
        target    = "/var/lib/docker"
        source    = "/var/lib/docker"
        type      = "bind"
        read_only = true
      }

      mounts {
        target    = "/dev/disk"
        source    = "/dev/disk"
        type      = "bind"
        read_only = true
      }
    }
  }

  mode {
    global = true
  }

  endpoint_spec {
    ports {
      target_port    = 8080
      published_port = 8080
      publish_mode   = "host"
    }
  }
}
