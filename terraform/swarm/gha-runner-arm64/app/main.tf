resource "docker_service" "gha_runner" {
  name = "gha-runner-arm64"

  dynamic "auth" {
    for_each = try(var.provider_config.registry_auth, null) == null ? [] : [var.provider_config.registry_auth]

    content {
      server_address = try(auth.value.address, "ghcr.io")
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    placement {
      constraints = var.github_runner_constraints
    }

    container_spec {
      image = var.github_runner_image
      user  = "0:0"

      env = {
        GH_RUNNER_URL           = var.github_runner_url
        GH_RUNNER_TOKEN         = var.github_runner_token
        GH_RUNNER_ACCESS_TOKEN  = var.github_runner_access_token
        GH_RUNNER_NAME          = "${var.github_runner_name}-{{.Task.Slot}}-{{.Task.ID}}"
        GH_RUNNER_LABELS        = var.github_runner_labels
        GH_RUNNER_WORKDIR       = var.github_runner_workdir
        GH_RUNNER_EPHEMERAL     = tostring(var.github_runner_ephemeral)
        GH_RUNNER_DISABLEUPDATE = tostring(var.github_runner_disableupdate)
        GH_RUNNER_REMOVE_TOKEN  = var.github_runner_remove_token
        RUNNER_ALLOW_RUNASROOT  = "1"
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

      dynamic "mounts" {
        for_each = var.enable_shared_tfvars_mount ? [var.shared_tfvars_volume_name] : []

        content {
          type   = "volume"
          source = mounts.value
          target = var.shared_tfvars_mount_target

          volume_options {
            driver_name    = var.shared_tfvars_volume_driver
            driver_options = var.shared_tfvars_volume_driver_opts
            no_copy        = false
          }
        }
      }

      healthcheck {
        test = ["CMD-SHELL", "test -f /tmp/gha-runner-ready"]

        interval     = "30s"
        timeout      = "10s"
        retries      = 5
        start_period = "30s"
      }
    }
  }

  mode {
    replicated {
      replicas = var.github_runner_replicas
    }
  }
}
