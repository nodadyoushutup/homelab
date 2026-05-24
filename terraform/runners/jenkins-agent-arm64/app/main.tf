# Standalone Docker containers on the ARM64 pool host (`terraform/components/arm64.tfvars`).

resource "docker_volume" "agent_home" {
  for_each = local.agent_definitions

  name   = "${var.home_volume_name_prefix}-${each.value.safe_name}"
  driver = "local"
}

resource "docker_volume" "agent_repo" {
  count = local.repo_mount_enabled ? 1 : 0

  name = "${var.service_name_prefix}-nfs-homelab"

  driver      = "local"
  driver_opts = local.nfs_driver_opts
}

resource "docker_volume" "extra_mounts" {
  for_each = local.extra_mounts_by_name

  name        = each.value.name
  driver      = each.value.driver
  driver_opts = each.value.driver_opts
}

resource "docker_container" "jenkins_agent" {
  for_each = local.agent_definitions

  name  = each.value.name
  image = var.agent_image

  restart = "always"

  group_add = var.kvm_supplementary_groups

  dns = var.dns_nameservers

  env = toset([
    for key, value in merge(local.agent_env, {
      JENKINS_URL        = var.jenkins_url
      JENKINS_AGENT_NAME = each.value.name
    }) : "${key}=${value}"
  ])

  devices {
    host_path      = "/dev/kvm"
    container_path = "/dev/kvm"
    permissions    = "rwm"
  }

  mounts {
    type   = "volume"
    source = docker_volume.agent_home[each.key].name
    target = each.value.remote_fs
  }

  mounts {
    type   = "bind"
    source = "/var/run/docker.sock"
    target = "/var/run/docker.sock"
  }

  mounts {
    type   = "bind"
    source = var.engine_visible_build_path
    target = var.engine_visible_build_path
  }

  dynamic "mounts" {
    for_each = local.repo_mount_enabled ? [1] : []

    content {
      type   = "volume"
      source = docker_volume.agent_repo[0].name
      target = local.repo_mount_target
    }
  }

  dynamic "mounts" {
    for_each = local.extra_mounts_by_name

    content {
      type   = "volume"
      source = docker_volume.extra_mounts[mounts.key].name
      target = mounts.value.target
    }
  }
}
