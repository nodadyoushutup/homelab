# locals.tf
# Single source of truth for cloud-image-repository Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "cloud-image-repository"
  network_name  = "cloud-image-repository"
  network_alias = "cloud-image-repository"
  volume_name   = "cloud-image-repository-data"

  target_port    = 8080
  published_port = 18088
  data_mount     = "/data"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
