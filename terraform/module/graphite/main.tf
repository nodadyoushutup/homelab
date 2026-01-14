locals {
  # Order matches Swarm's platform reporting (aarch64 then arm64) to avoid churny platform diffs.
  allowed_platforms = [
    {
      os           = "linux"
      architecture = "aarch64"
    },
    {
      os           = "linux"
      architecture = "arm64"
    }
  ]
}

resource "docker_network" "graphite" {
  name   = "graphite-net"
  driver = "overlay"
}

resource "docker_volume" "graphite_data" {
  name = "graphite-data"
}

resource "terraform_data" "platforms" {
  input = local.allowed_platforms
}

resource "docker_service" "graphite" {
  name = "graphite"
  depends_on = [terraform_data.platforms]

  task_spec {
    placement {
      dynamic "platforms" {
        for_each = local.allowed_platforms

        content {
          os           = platforms.value.os
          architecture = platforms.value.architecture
        }
      }

      constraints = ["node.labels.role==swarm-cp-0"]
    }

    networks_advanced {
      name    = docker_network.graphite.id
      aliases = ["graphite"]
    }

    container_spec {
      image = "graphiteapp/graphite-statsd:1.1.10-5@sha256:ceb163a8f237ea1a5d2839589f6b5b7aef05153b12b05ed9fe3cec12fe10cf43"

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/opt/graphite/storage"
        source = docker_volume.graphite_data.name
        type   = "volume"
      }
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

  lifecycle {
    ignore_changes = [
      task_spec[0].placement[0].platforms,
    ]
    replace_triggered_by = [
      terraform_data.platforms,
    ]
  }
}
