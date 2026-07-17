# locals.tf
# Single source of truth for qBittorrent exporter Swarm service values (resources read local.* only).

locals {
  env                          = var.env
  instances                    = var.instances
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name_prefix     = "qbittorrent-exporter"
  network_name            = "qbittorrent-exporter"
  prometheus_network_name = "prometheus"

  replicas       = 1
  container_port = 8090

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
