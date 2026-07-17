# locals.tf
# Single source of truth for grafana-postgres Swarm service values (resources read local.* only).

locals {
  env                          = var.env
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "grafana-postgres"
  network_name  = "grafana-postgres"
  network_alias = "postgres"
  volume_name   = "grafana-postgres-data"

  postgres_port = 5432
  data_mount    = "/var/lib/postgresql"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
