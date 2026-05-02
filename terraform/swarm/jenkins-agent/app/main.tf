locals {
  casc_config     = yamldecode(file(var.casc_config_path))
  requested_nodes = try(local.casc_config.jenkins.nodes, [])
  agent_definitions = {
    for node in local.requested_nodes : trimspace(tostring(node.permanent.name)) => {
      name      = trimspace(tostring(node.permanent.name))
      safe_name = lower(replace(trimspace(tostring(node.permanent.name)), "/[^0-9A-Za-z_.-]/", "-"))
      remote_fs = trimspace(tostring(try(node.permanent.remoteFS, var.default_remote_fs)))
      placement_constraints = trimspace(tostring(try(node.permanent.nodeDescription, ""))) != "" ? [
        "node.hostname==${trimspace(tostring(node.permanent.nodeDescription))}"
      ] : var.placement_constraints
    } if try(trimspace(tostring(node.permanent.name)) != "", false)
  }
  default_env = {
    JENKINS_SECRETS_DIR = var.agent_secrets_dir
  }
  agent_env = merge(local.default_env, var.env)
  extra_mounts_by_name = {
    for mount in var.mounts : mount.name => mount
  }
}

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
    for_each = try(var.provider_config.registry_auth, null) == null ? [] : [var.provider_config.registry_auth]

    content {
      server_address = try(auth.value.address, "ghcr.io")
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

      dynamic "mounts" {
        for_each = var.enable_shared_tfvars_mount ? [1] : []

        content {
          type   = "bind"
          source = var.shared_tfvars_host_path
          target = var.shared_tfvars_mount_target
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
