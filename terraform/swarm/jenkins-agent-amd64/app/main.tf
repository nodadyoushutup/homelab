resource "docker_volume" "agent_home" {
  for_each = local.agent_definitions

  name   = "${var.home_volume_name_prefix}-${each.value.safe_name}"
  driver = "local"
}

resource "docker_volume" "extra_mounts" {
  for_each = local.extra_mounts_by_name

  name        = each.value.name
  driver      = each.value.driver
  driver_opts = each.value.driver_opts
}

resource "docker_service" "jenkins_agent" {
  for_each = local.agent_definitions

  name = startswith(each.value.safe_name, "${var.service_name_prefix}-") ? each.value.safe_name : "${var.service_name_prefix}-${each.value.safe_name}"

  dynamic "auth" {
    for_each = local.docker_service_pull_auth_map

    content {
      server_address = auth.value.server_address
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    placement {
      constraints = each.value.placement_constraints
    }

    networks_advanced {
      name    = var.network_name
      aliases = []
    }

    container_spec {
      image = var.agent_image
      env = merge(local.agent_env, {
        JENKINS_URL        = var.jenkins_url
        JENKINS_AGENT_NAME = each.value.name
      })

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.agent_home[each.key].name
        target = each.value.remote_fs
      }

      mounts {
        target = "/dev/kvm"
        source = "/dev/kvm"
        type   = "bind"
      }

      dynamic "mounts" {
        for_each = local.enable_shared_tfvars_mount_effective ? [var.shared_tfvars_volume_name] : []

        content {
          type   = "volume"
          source = mounts.value
          target = local.swarm_nfs_config_target

          volume_options {
            driver_name    = var.shared_tfvars_volume_driver
            driver_options = local.shared_tfvars_volume_driver_opts_effective
            no_copy        = false
          }
        }
      }

      dynamic "mounts" {
        for_each = local.swarm_nfs_code_mounts

        content {
          type   = mounts.value.type
          source = mounts.value.source
          target = mounts.value.target

          volume_options {
            driver_name    = mounts.value.volume_options.driver_name
            driver_options = mounts.value.volume_options.driver_options
            no_copy        = mounts.value.volume_options.no_copy
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
      replicas = 1
    }
  }
}
