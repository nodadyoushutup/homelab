locals {
  telegraf_config_hash  = substr(filemd5("${path.module}/telegraf.conf"), 0, 12)
  telegraf_force_update = parseint(substr(local.telegraf_config_hash, 0, 8), 16)
}




locals {
  docker_registry_auths = coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])
}
