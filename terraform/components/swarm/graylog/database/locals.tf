# locals.tf
# Single source of truth for graylog-mongodb Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

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
