# main.tf
# Global and swarm-wk-4-pinned container-housekeeping Swarm services.

resource "docker_service" "container_housekeeping" {
  name = "container-housekeeping"

  task_spec {
    placement {
      constraints = ["node.labels.role!=swarm-wk-4"]

      platforms {
        os           = "linux"
        architecture = "amd64"
      }

      platforms {
        os           = "linux"
        architecture = "arm64"
      }

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    container_spec {
      image   = "docker:29.6.2-cli" # Literal tag for Renovate (not a var/local; no digest).
      command = ["/bin/sh", "-ec"]
      args    = [local.cleanup_script]

      mounts {
        target = "/var/run/docker.sock"
        source = "/var/run/docker.sock"
        type   = "bind"
      }
    }

    restart_policy {
      condition    = "on-failure"
      delay        = "30s"
      max_attempts = 0
      window       = "0s"
    }
  }

  mode {
    global = true
  }

  lifecycle {
    ignore_changes = [task_spec[0].placement[0].platforms]
  }
}

resource "docker_service" "container_housekeeping_wk4" {
  name = "container-housekeeping-wk4"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-wk-4"]

      platforms {
        os           = "linux"
        architecture = "arm64"
      }
    }

    container_spec {
      image   = "docker:29.6.2-cli" # Literal tag for Renovate (not a var/local; no digest).
      command = ["/bin/sh", "-ec"]
      args    = [local.cleanup_script]

      mounts {
        target = "/var/run/docker.sock"
        source = "/var/run/docker.sock"
        type   = "bind"
      }
    }

    restart_policy {
      condition    = "on-failure"
      delay        = "30s"
      max_attempts = 0
      window       = "0s"
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }
}
