# main.tf
# Overlay network, volumes, and Jenkins controller Swarm service.

resource "docker_network" "jenkins_controller" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "jenkins_controller_home" {
  name   = local.home_volume_name
  driver = "local"
}

resource "docker_volume" "extra_mounts" {
  for_each = local.extra_mounts_by_name

  name        = each.value.name
  driver      = each.value.driver
  driver_opts = each.value.driver_opts
}

resource "docker_service" "jenkins_controller" {
  name = local.service_name

  task_spec {
    force_update = local.config_force_update

    dynamic "placement" {
      for_each = local.placement == null ? [] : [local.placement]

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
      aliases = [local.service_dns_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image = "ghcr.io/nodadyoushutup/jenkins-controller:0.0.18"
      env   = local.controller_env

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.jenkins_controller_home.name
        target = local.home_mount_target
      }

      dynamic "mounts" {
        for_each = local.enable_shared_repo_mount_effective ? [local.shared_tfvars_volume_name] : []

        content {
          type   = "volume"
          source = mounts.value
          target = local.repo_mount_target

          volume_options {
            driver_name    = local.shared_tfvars_volume_driver
            driver_options = local.shared_repo_volume_driver_opts_effective
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
      replicas = local.controller_replicas
    }
  }

  endpoint_spec {
    ports {
      target_port    = local.controller_target_port
      published_port = local.controller_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = local.agent_target_port
      published_port = local.agent_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
