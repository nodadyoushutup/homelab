resource "docker_network" "dozzle" {
  name   = "dozzle"
  driver = "overlay"
}

resource "docker_service" "dozzle" {
  name = "dozzle"

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
      name        = docker_network.dozzle.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "amir20/dozzle:v9.0.3@sha256:2d59d09503f2c947133a4f231fdeb1f4c99e23aa0d4137f81bb1a6318e0e06cf"

      env = {
        DOZZLE_MODE = "swarm"
      }

      dynamic "dns_config" {
        for_each = var.dns_nameservers == null ? [] : [var.dns_nameservers]

        content {
          nameservers = dns_config.value
        }
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
}
