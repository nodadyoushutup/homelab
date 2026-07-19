# locals.tf
# Single source of truth for prometheus-pve-exporter Swarm service values (resources read local.* only).

locals {
  disable_config_collector = var.disable_config_collector
  dns_nameservers          = var.dns_nameservers
  endpoint_host            = var.endpoint_host
  env                      = var.env
  placement                = var.placement
  published_port           = var.published_port
  pve_targets              = var.pve_targets
  docker_selected          = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }
  verify_ssl = var.verify_ssl

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
