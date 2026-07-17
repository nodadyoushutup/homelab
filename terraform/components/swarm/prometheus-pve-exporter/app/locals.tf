# locals.tf
# Single source of truth for prometheus-pve-exporter Swarm service values (resources read local.* only).

locals {
  disable_config_collector     = var.disable_config_collector
  dns_nameservers              = var.dns_nameservers
  endpoint_host                = var.endpoint_host
  env                          = var.env
  placement                    = var.placement
  published_port               = var.published_port
  pve_targets                  = var.pve_targets
  swarm_docker_provider_config = var.swarm_docker_provider_config
  verify_ssl                   = var.verify_ssl

  service_name  = "prometheus-pve-exporter"
  network_name  = "prometheus-pve-exporter"
  internal_port = 9221

  prometheus_network_name = "prometheus"

  exporter_env = merge(
    {
      PVE_VERIFY_SSL = local.verify_ssl ? "true" : "false"
    },
    local.env,
  )

  exporter_args = local.disable_config_collector ? [
    "--no-collector.config",
  ] : []

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
