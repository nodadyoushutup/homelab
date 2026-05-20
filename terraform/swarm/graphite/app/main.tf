resource "docker_network" "graphite" {
  name   = "graphite-net"
  driver = "overlay"
}

resource "docker_volume" "graphite_data" {
  name   = "graphite-data"
  driver = "local"
}

resource "docker_service" "graphite" {
  name = "graphite"

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
      name    = docker_network.graphite.id
      aliases = ["graphite"]
    }

    container_spec {
      image = "graphiteapp/graphite-statsd:1.1.10-5@sha256:ceb163a8f237ea1a5d2839589f6b5b7aef05153b12b05ed9fe3cec12fe10cf43"

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/opt/graphite/storage"
        source = docker_volume.graphite_data.name
        type   = "volume"
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
      target_port    = 8080
      published_port = 8081
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 2003
      published_port = 2003
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 2003
      published_port = 2003
      protocol       = "udp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 2004
      published_port = 2004
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 8125
      published_port = 8125
      protocol       = "udp"
      publish_mode   = "ingress"
    }
  }
}
