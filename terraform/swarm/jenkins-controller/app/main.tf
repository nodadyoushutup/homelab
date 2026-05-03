locals {
  casc_hash = substr(sha256(file(var.casc_config_path)), 0, 12)

  config_force_update = parseint(substr(local.casc_hash, 0, 8), 16)
  default_env = {
    CASC_JENKINS_CONFIG = var.casc_config_container_path
    SECRETS_DIR         = var.agent_secrets_dir
  }
  controller_env = merge(local.default_env, var.env)
  extra_mounts_by_name = {
    for mount in var.mounts : mount.name => mount
  }
}

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
    for_each = try(var.provider_config.registry_auth, null) == null ? [] : [var.provider_config.registry_auth]

    content {
      server_address = try(auth.value.address, "ghcr.io")
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    force_update = local.config_force_update

    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
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
