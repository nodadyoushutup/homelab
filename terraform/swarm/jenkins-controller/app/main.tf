resource "docker_network" "jenkins_controller" {
  name   = var.network_name
  driver = "overlay"
}

resource "docker_volume" "jenkins_controller_home" {
  name   = var.home_volume_name
  driver = "local"
}

resource "docker_volume" "extra_mounts" {
  for_each = local.extra_mounts_by_name

  name        = each.value.name
  driver      = each.value.driver
  driver_opts = each.value.driver_opts
}

resource "docker_service" "jenkins_controller" {
  name = var.service_name

  dynamic "auth" {
    for_each = local.docker_service_pull_auth_map

    content {
      server_address = auth.value.server_address
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    force_update = local.config_force_update

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
      name    = docker_network.jenkins_controller.id
      aliases = [var.service_dns_alias]
    }

    container_spec {
      image = var.controller_image
      env   = local.controller_env

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.jenkins_controller_home.name
        target = var.home_mount_target
      }

      dynamic "mounts" {
        for_each = local.enable_shared_tfvars_mount_effective ? [var.shared_tfvars_volume_name] : []

        content {
          type   = "volume"
          source = mounts.value
          target = var.shared_tfvars_mount_target

          volume_options {
            driver_name    = var.shared_tfvars_volume_driver
            driver_options = local.shared_tfvars_volume_driver_opts_effective
            no_copy        = false
          }
        }
      }

      dynamic "mounts" {
        for_each = local.extra_mounts_by_name

        content {
          type   = "volume"
          source = docker_volume.extra_mounts[mounts.key].name
          target = mounts.value.target

          dynamic "volume_options" {
            for_each = mounts.value.no_copy ? [1] : []

            content {
              no_copy = true
            }
          }
        }
      }
      healthcheck {
        test         = ["CMD-SHELL", "curl --silent --show-error --fail http://127.0.0.1:8080/login > /dev/null || exit 1"]
        interval     = "30s"
        timeout      = "5s"
        retries      = 6
        start_period = "1m"
      }
    }

    restart_policy {
      condition    = "on-failure"
      delay        = "10s"
      max_attempts = 3
      window       = "2m"
    }
  }

  mode {
    replicated {
      replicas = var.controller_replicas
    }
  }

  endpoint_spec {
    ports {
      target_port    = var.controller_target_port
      published_port = var.controller_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = var.agent_target_port
      published_port = var.agent_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
