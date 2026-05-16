# Standalone Docker containers on the pool host (`provider_config.docker` from docker_swarm.tfvars,
# merged after docker_arm64.tfvars by pipelines/terraform/swarm/gha-runner-arm64/app.sh).
# Uses `docker_container` + `devices` so `/dev/kvm` gets proper cgroup permissions (unlike Swarm services).

moved {
  from = docker_volume.gha_runner_config
  to   = docker_volume.gha_runner_nfs["config"]
}

resource "docker_volume" "gha_runner_nfs" {
  for_each = local.gha_runner_nfs_volume_keys

  name = "${replace(local.runner_name, "_", "-")}-nfs-${each.key}"

  driver = "local"
  driver_opts = {
    type   = trimspace(var.swarm_nfs_volume_type)
    o      = trimspace(var.swarm_nfs_volume_o_rw)
    device = each.key == "code" ? trimspace(var.swarm_nfs_code_device) : trimspace(var.swarm_nfs_config_device)
  }
}

resource "docker_container" "gha_runner" {
  count = var.replicas

  name  = "${local.runner_name}-${count.index + 1}"
  image = local.runner_image

  restart = "always"
  user    = "0:0"

  group_add = ["kvm"]

  dns = var.dns_nameservers

  env = toset([
    "GH_RUNNER_URL=${var.url}",
    "GH_RUNNER_TOKEN=${var.registration_token}",
    "GH_RUNNER_ACCESS_TOKEN=${var.access_token}",
    "GH_RUNNER_NAME=${local.runner_name}-${count.index + 1}",
    "GH_RUNNER_LABELS=${local.runner_labels}",
    "GH_RUNNER_WORKDIR=${local.runner_workdir}",
    "GH_RUNNER_EPHEMERAL=${local.runner_ephemeral}",
    "GH_RUNNER_DISABLEUPDATE=${local.runner_disableupdate}",
    "RUNNER_ALLOW_RUNASROOT=1",
    "HARBOR_BUILD_TMP_PARENT=${var.engine_visible_build_path}",
    # Verbose Packer / plugin stderr (e.g. QEMU launch failures) in Actions job logs.
    "PACKER_LOG=1",
  ])

  devices {
    host_path      = "/dev/kvm"
    container_path = "/dev/kvm"
    permissions    = "rwm"
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
    for_each = local.gha_runner_nfs_volume_keys

    content {
      type   = "volume"
      source = docker_volume.gha_runner_nfs[mounts.key].name
      target = lookup(local.gha_runner_nfs_container_targets, mounts.key)
    }
  }

  healthcheck {
    test         = ["CMD-SHELL", "test -f /tmp/gha-runner-ready"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }
}
