# locals.tf
# Single source of truth for GHA runner (AMD64) Docker values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  env                          = var.env
  nfs                          = var.nfs
  replicas                     = var.replicas
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name_prefix = "gha-runner-amd64"
  nfs_volume_name     = "${local.service_name_prefix}-nfs-homelab"
  engine_build_path   = "/var/lib/gha-runner-engine-build"

  replica_indexes = { for n in range(1, local.replicas + 1) : tostring(n) => n }

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
