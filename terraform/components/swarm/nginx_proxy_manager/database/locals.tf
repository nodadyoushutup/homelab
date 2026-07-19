# locals.tf
# Single source of truth for nginx-proxy-manager-mysql Swarm service values (resources read local.* only).

locals {
  env             = var.env
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

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
