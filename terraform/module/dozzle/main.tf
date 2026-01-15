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

resource "docker_network" "dozzle" {
  name   = "dozzle"
  driver = "overlay"
}

resource "terraform_data" "platforms" {
  input = local.allowed_platforms
}

resource "docker_service" "dozzle" {
  name = "dozzle"
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
    }

    networks_advanced {
      name        = docker_network.dozzle.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "amir20/dozzle:v9.0.1@sha256:a7529f02748a9520a4f372f7b349e099bb0bc6ae93c2be9d85945f51d45f8967"

      env = {
        DOZZLE_MODE = "swarm"
      }

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/var/run/docker.sock"
        source = "/var/run/docker.sock"
        type   = "bind"
      }

      healthcheck {
        test         = ["CMD", "/dozzle", "healthcheck"]
        interval     = "10s"
        timeout      = "5s"
        retries      = 30
        start_period = "1m"
      }
    }
  }

  mode {
    global = true
  }

  endpoint_spec {
    ports {
      target_port    = 8080
      published_port = 8888
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
