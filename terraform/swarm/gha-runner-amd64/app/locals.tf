locals {
  nfs_device       = trimspace(var.nfs.device)
  nfs_volume_type  = trimspace(var.nfs.volume.type)
  nfs_volume_opts  = trimspace(var.nfs.volume.opts)
  nfs_mount_target = local.nfs_device != "" ? trimspace(element(split(":", local.nfs_device), length(split(":", local.nfs_device)) - 1)) : ""
  nfs_driver_opts = merge({
    type = local.nfs_volume_type
    o    = local.nfs_volume_opts
  }, local.nfs_device != "" ? { device = local.nfs_device } : {})
  nfs_ready = nonsensitive(
    local.nfs_device != "" &&
    local.nfs_volume_type != "" &&
    local.nfs_volume_opts != ""
  )

  gha_runner_repo_mount = local.nfs_ready
}

locals {
  runner_image         = "ghcr.io/nodadyoushutup/gha-runner:0.1.1"
  runner_name          = "homelab-gha-runner-amd64"
  runner_labels        = "self-hosted,linux,homelab,amd64,build,kvm"
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
