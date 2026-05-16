resource "docker_network" "dozzle" {
  name   = "dozzle"
  driver = "overlay"
}

resource "docker_service" "dozzle" {
  name = "dozzle"

  task_spec {
    placement {
      platforms {
        os           = "linux"
        architecture = "aarch64"
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
        nameservers = var.dns_nameservers
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
