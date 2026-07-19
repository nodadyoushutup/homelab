# locals.tf
# Single source of truth for Grafana Swarm service values (resources read local.* only).

locals {
  env             = var.env
  ini_path        = var.ini_path
  placement       = var.placement
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

  service_name  = "grafana"
  network_name  = "grafana-app"
  network_alias = "grafana"
  volume_name   = "grafana-app"

  postgres_network_name        = "grafana-postgres"
  victoriametrics_network_name = "victoriametrics-net"

  data_mount = "/var/lib/grafana"
  ini_mount  = "/etc/grafana/grafana.ini"

  target_port    = 3000
  published_port = 3000

  # Config name carries a content hash so updates roll a new docker_config revision.
  ini_hash         = substr(filemd5(local.ini_path), 0, 12)
  ini_force_update = parseint(substr(local.ini_hash, 0, 8), 16)
  config_name      = "grafana-ini-${local.ini_hash}"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
