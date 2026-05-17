# Standalone Docker containers on the AMD64 pool host (`provider_config.docker` from
# docker_amd64.tfvars). Uses `docker_container` + `devices` for `/dev/kvm` (unlike Swarm services).

resource "docker_volume" "agent_home" {
  for_each = local.agent_definitions

  name   = "${var.home_volume_name_prefix}-${each.value.safe_name}"
  driver = "local"
}

resource "docker_volume" "agent_nfs" {
  for_each = local.jenkins_agent_nfs_volume_keys

  name = "${var.service_name_prefix}-nfs-${each.key}"

  driver = "local"
  driver_opts = {
    type   = trimspace(var.swarm_nfs_volume_type)
    o      = trimspace(var.swarm_nfs_volume_o_rw)
    device = local.jenkins_agent_nfs_devices[each.key]
  }
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

  group_add = ["kvm"]

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
    for_each = local.jenkins_agent_nfs_volume_keys

    content {
      type   = "volume"
      source = docker_volume.agent_nfs[mounts.key].name
      target = lookup(local.jenkins_agent_nfs_container_targets, mounts.key)
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
