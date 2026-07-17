# locals.tf
# Single source of truth for VictoriaMetrics Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "victoriametrics"
  network_name  = "victoriametrics-net"
  network_alias = "victoriametrics"

  volume_name          = "victoriametrics-data"
  storage_mount_target = "/victoria-metrics-data"

  replicas = 1

  http_port = {
    target_port    = 8428
    published_port = 8428
    protocol       = "tcp"
    publish_mode   = "ingress"
  }

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
