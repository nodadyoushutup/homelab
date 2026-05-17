locals {
  # Booleans only (no secret strings): required so derived toset() is not marked sensitive — for_each cannot use sensitive collections.
  swarm_nfs_ready = nonsensitive(
    length(trimspace(var.swarm_nfs_code_device)) > 0 &&
    length(trimspace(var.swarm_nfs_config_device)) > 0 &&
    length(trimspace(var.swarm_nfs_volume_type)) > 0 &&
    length(trimspace(var.swarm_nfs_volume_o_rw)) > 0
  )

  # Literal keys only: for_each cannot use a map keyed/valued from sensitive nfs.tfvars vars.
  gha_runner_nfs_volume_keys = local.swarm_nfs_ready ? toset(["code", "config"]) : toset([])

  # Mount path inside the container: last segment of device (e.g. ":/mnt/eapp/code" -> "/mnt/eapp/code").
  gha_runner_nfs_container_targets = local.swarm_nfs_ready ? {
    code   = trimspace(element(split(":", trimspace(var.swarm_nfs_code_device)), length(split(":", trimspace(var.swarm_nfs_code_device))) - 1))
    config = trimspace(element(split(":", trimspace(var.swarm_nfs_config_device)), length(split(":", trimspace(var.swarm_nfs_config_device))) - 1))
  } : {}
}
locals {
  runner_image         = "ghcr.io/nodadyoushutup/gha-runner:0.0.6"
  runner_name          = "homelab-gha-runner-amd64"
  runner_labels        = "self-hosted,linux,homelab,amd64,build,kvm"
  runner_workdir       = "_work"
  runner_ephemeral     = true
  runner_disableupdate = true
}




locals {
  provider_config = merge(var.swarm_docker_provider_config, var.provider_config)
  docker_registry_auths = (
    try(local.provider_config.registry_auths, null) != null
    ? local.provider_config.registry_auths
    : (
      try(local.provider_config.registry_auth, null) != null
      ? [local.provider_config.registry_auth]
      : []
    )
  )
  # docker_container uses provider-level registry_auth; pick the entry for this image's registry.
  runner_registry_host = split("/", local.runner_image)[0]
  runner_registry_matching_auths = [
    for a in local.docker_registry_auths : a
    if coalesce(try(a.address, null), "ghcr.io") == local.runner_registry_host
  ]
  docker_registry_auth_for_runner_image = (
    length(local.runner_registry_matching_auths) > 0 ? local.runner_registry_matching_auths[0] : null
  )
}
