locals {
  nfs_mount_target = trimspace(var.nfs.target)
  nfs_driver_opts  = var.nfs.driver_options
  nfs_ready = nonsensitive(
    local.nfs_mount_target != "" &&
    length(local.nfs_driver_opts) > 0 &&
    trimspace(lookup(local.nfs_driver_opts, "type", "")) != "" &&
    trimspace(lookup(local.nfs_driver_opts, "device", "")) != "" &&
    trimspace(lookup(local.nfs_driver_opts, "o", "")) != ""
  )

  gha_runner_repo_mount = local.nfs_ready
}

locals {
  runner_image         = "ghcr.io/nodadyoushutup/gha-runner:0.1.1"
  runner_name          = "homelab-gha-runner-arm64"
  runner_labels        = "self-hosted,linux,homelab,arm64,build,kvm"
  runner_workdir       = "_work"
  runner_ephemeral     = true
  runner_disableupdate = true
}

locals {
  # docker_container uses provider-level registry_auth; pick the entry for this image's registry.
  runner_registry_host = split("/", local.runner_image)[0]
  runner_registry_matching_auths = [
    for a in coalesce(try(var.swarm_docker_provider_config.registry_auths, null), []) : a
    if coalesce(try(a.address, null), "ghcr.io") == local.runner_registry_host
  ]
  docker_registry_auth_for_runner_image = (
    length(local.runner_registry_matching_auths) > 0 ? local.runner_registry_matching_auths[0] : null
  )
}
