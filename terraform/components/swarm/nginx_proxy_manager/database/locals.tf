# locals.tf
# Single source of truth for nginx-proxy-manager-mysql Swarm service values (resources read local.* only).

locals {
  env                          = var.env
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "nginx-proxy-manager-mysql"
  network_name  = "nginx-proxy-manager-mysql"
  network_alias = "mysql"
  volume_name   = "nginx-proxy-manager-mysql-data"

  mysql_port = 3306
  data_mount = "/var/lib/mysql"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
