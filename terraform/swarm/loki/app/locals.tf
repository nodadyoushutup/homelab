locals {
  loki_config_hash  = substr(filemd5(var.loki_config_path), 0, 12)
  loki_force_update = parseint(substr(local.loki_config_hash, 0, 8), 16)
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
