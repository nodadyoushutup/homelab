# locals.tf
# Single source of truth for qBittorrent exporter Swarm service values (resources read local.* only).

locals {
  env             = var.env
  instances       = var.instances
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

  service_name_prefix     = "qbittorrent-exporter"
  network_name            = "qbittorrent-exporter"
  prometheus_network_name = "prometheus"

  replicas       = 1
  container_port = 8090

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
