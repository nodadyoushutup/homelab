resource "docker_network" "node_exporter" {
  name   = "node-exporter"
  driver = "overlay"
}

resource "docker_service" "node_exporter" {
  name = "node-exporter"
  
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
      name        = docker_network.node_exporter.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "prom/node-exporter:v1.10.2@sha256:3ac34ce007accad95afed72149e0d2b927b7e42fd1c866149b945b84737c62c3"

      args = [
        "--path.procfs=/host/proc",
        "--path.sysfs=/host/sys",
        "--path.rootfs=/host/rootfs",
        "--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($|/)",
        "--collector.filesystem.ignored-fs-types=^(autofs|proc|sysfs|tmpfs|devtmpfs|devpts|overlay|aufs)$",
      ]

      dynamic "dns_config" {
        for_each = var.dns_nameservers == null ? [] : [var.dns_nameservers]

        content {
          nameservers = dns_config.value
        }
      }

      mounts {
        target    = "/host/proc"
        source    = "/proc"
        type      = "bind"
        read_only = true
      }

      mounts {
        target    = "/host/sys"
        source    = "/sys"
        type      = "bind"
        read_only = true
      }

      mounts {
        target    = "/host/rootfs"
        source    = "/"
        type      = "bind"
        read_only = true
      }

      mounts {
        target    = "/etc/host_hostname"
        source    = "/etc/hostname"
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
      target_port    = 9100
      published_port = 9100
      publish_mode   = "host"
    }
  }
}
