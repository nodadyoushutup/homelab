# main.tf
# Standalone Docker containers on the AMD64 pool host (`.config/terraform/components/swarm/amd64.tfvars`).
# Uses `docker_container` + `devices` so `/dev/kvm` gets proper cgroup permissions (unlike Swarm services).

resource "docker_volume" "nfs_homelab" {
  name        = local.nfs_volume_name
  driver      = "local"
  driver_opts = local.nfs.driver_options
}

resource "docker_container" "gha_runner" {
  for_each = local.replica_indexes

  name  = "homelab-${local.service_name_prefix}-${each.key}"
  image = "ghcr.io/nodadyoushutup/gha-runner:0.1.2"

  restart = "always"
  user    = "0:0"

  group_add = ["kvm"]

  dns = local.dns_nameservers

  env = toset([
    for key, value in merge(local.env, {
      GH_RUNNER_NAME = "homelab-${local.service_name_prefix}-${each.key}"
    }) : "${key}=${value}"
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

  # Must match GHA_ENGINE_BUILD_TMP_PARENT in app.tfvars `env` (nested docker bind-mounts).
  mounts {
    type   = "bind"
    source = local.engine_build_path
    target = local.engine_build_path
  }

  mounts {
    type   = "volume"
    source = docker_volume.nfs_homelab.name
    target = local.nfs.target
  }
}
