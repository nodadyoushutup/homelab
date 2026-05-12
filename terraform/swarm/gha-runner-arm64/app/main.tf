# Standalone Docker containers on the pool host (see `provider_config.docker` in tfvars).
# Uses `docker_container` + `devices` so `/dev/kvm` gets proper cgroup permissions (unlike Swarm services).

resource "docker_volume" "gha_runner_config" {
  name = "${replace(var.github_runner_name, "_", "-")}-nfs-config"

  driver = "local"
  driver_opts = {
    type   = "nfs"
    o      = "addr=192.168.1.100,nfsvers=4.2,rw"
    device = ":/mnt/eapp/config"
  }
}

resource "docker_container" "gha_runner" {
  count = var.github_runner_replicas

  name  = "${var.github_runner_name}-${count.index + 1}"
  image = var.github_runner_image

  restart = "always"
  user    = "0:0"

  group_add = ["kvm"]

  dns = tolist(["192.168.1.1", "1.1.1.1", "8.8.8.8"])

  env = toset([
    "GH_RUNNER_URL=${var.github_runner_url}",
    "GH_RUNNER_TOKEN=${var.github_runner_token}",
    "GH_RUNNER_ACCESS_TOKEN=${var.github_runner_access_token}",
    "GH_RUNNER_NAME=${var.github_runner_name}-${count.index + 1}",
    "GH_RUNNER_LABELS=${var.github_runner_labels}",
    "GH_RUNNER_WORKDIR=${var.github_runner_workdir}",
    "GH_RUNNER_EPHEMERAL=${var.github_runner_ephemeral}",
    "GH_RUNNER_DISABLEUPDATE=${var.github_runner_disableupdate}",
    "GH_RUNNER_REMOVE_TOKEN=${var.github_runner_remove_token}",
    "RUNNER_ALLOW_RUNASROOT=1",
    "HARBOR_BUILD_TMP_PARENT=${var.github_runner_engine_visible_build_path}",
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
    source = var.github_runner_engine_visible_build_path
    target = var.github_runner_engine_visible_build_path
  }

  mounts {
    type   = "volume"
    source = docker_volume.gha_runner_config.name
    target = "/mnt/eapp/config"
  }

  healthcheck {
    test         = ["CMD-SHELL", "test -f /tmp/gha-runner-ready"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }
}
