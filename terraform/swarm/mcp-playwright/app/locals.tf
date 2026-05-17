locals {
  service_name = "mcp-playwright"
  internal_port = 8931

  swarm_nfs_ready = (
    trimspace(var.swarm_nfs_code_device) != "" &&
    trimspace(var.swarm_nfs_config_device) != "" &&
    trimspace(var.swarm_nfs_volume_type) != "" &&
    trimspace(var.swarm_nfs_volume_o_rw) != "" &&
    trimspace(var.swarm_nfs_volume_o_ro) != ""
  )
  swarm_nfs_code_target = trimspace(element(split(":", trimspace(var.swarm_nfs_code_device)), length(split(":", trimspace(var.swarm_nfs_code_device))) - 1))
  swarm_nfs_code_mounts = local.swarm_nfs_ready ? [{
    type      = "volume"
    source    = "${local.service_name}-mnt-eapp-code"
    target    = local.swarm_nfs_code_target
    read_only = false
    volume_options = {
      driver_name = "local"
      driver_options = {
        type   = trimspace(var.swarm_nfs_volume_type)
        o      = trimspace(var.swarm_nfs_volume_o_rw)
        device = trimspace(var.swarm_nfs_code_device)
      }
      no_copy = false
    }
  }] : []
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
}
