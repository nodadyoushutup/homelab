# locals.tf
# Single source of truth for graylog-mongodb Swarm service values (resources read local.* only).

locals {
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

  service_name       = "graylog-mongodb"
  network_name       = "graylog-mongodb"
  network_alias      = "mongodb"
  data_volume_name   = "graylog-mongodb-data"
  config_volume_name = "graylog-mongodb-config"

  data_mount   = "/data/db"
  config_mount = "/data/configdb"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
