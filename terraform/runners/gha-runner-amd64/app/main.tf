# Standalone Docker containers on the AMD64 pool host (`terraform/components/amd64.tfvars`).
# Uses `docker_container` + `devices` so `/dev/kvm` gets proper cgroup permissions (unlike Swarm services).

resource "docker_volume" "nfs_homelab" {
  name        = "gha-runner-amd64-nfs-homelab"
  driver      = "local"
  driver_opts = var.nfs.driver_options
}

resource "docker_container" "gha_runner" {
  for_each = { for n in range(1, var.replicas + 1) : tostring(n) => n }

  name  = "homelab-gha-runner-amd64-${each.key}"
  image = var.image

  restart = "always"
  user    = "0:0"

  group_add = ["kvm"]

  dns = var.dns_nameservers

  env = toset([
    for key, value in merge(var.env, {
      GH_RUNNER_NAME = "homelab-gha-runner-amd64-${each.key}"
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

  # Must match HARBOR_BUILD_TMP_PARENT in app.tfvars `env` (Harbor nested docker bind-mounts).
  mounts {
    type   = "bind"
    source = "/var/lib/gha-runner-engine-build"
    target = "/var/lib/gha-runner-engine-build"
  }

  mounts {
    type   = "volume"
    source = docker_volume.nfs_homelab.name
    target = var.nfs.target
  }
}
