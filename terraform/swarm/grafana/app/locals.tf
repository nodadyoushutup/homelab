locals {
  grafana_ini_hash         = substr(filemd5(var.ini_path), 0, 12)
  grafana_ini_force_update = parseint(substr(local.grafana_ini_hash, 0, 8), 16)
}

locals {
  docker_registry_auths = coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])
}
