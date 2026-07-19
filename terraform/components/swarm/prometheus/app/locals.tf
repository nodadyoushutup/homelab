# locals.tf
# Single source of truth for Prometheus Swarm service values (resources read local.* only).

locals {
  config_path     = var.config_path
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

  service_name  = "prometheus"
  network_name  = "prometheus"
  network_alias = "prometheus"
  volume_name   = "prometheus-data"

  victoriametrics_network_name = "victoriametrics-net"

  data_mount   = "/prometheus"
  config_mount = "/etc/prometheus/prometheus.yml"

  target_port    = 9090
  published_port = 9090

  args = [
    "--config.file=${local.config_mount}",
    "--storage.tsdb.path=${local.data_mount}",
    "--storage.tsdb.retention.time=1h",
    "--web.enable-lifecycle",
    "--web.enable-admin-api",
  ]

  config_hash  = substr(filemd5(local.config_path), 0, 12)
  force_update = parseint(substr(local.config_hash, 0, 8), 16)
  config_name  = "prometheus-${local.config_hash}"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
