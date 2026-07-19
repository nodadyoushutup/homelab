# locals.tf
# Single source of truth for GHA runner (ARM64) Docker values (resources read local.* only).

locals {
  dns_nameservers = var.dns_nameservers
  env             = var.env
  replicas        = var.replicas
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

  # Compose the Docker NFS volume from the shared catalog (config-id terraform/nfs).
  nfs_selected = var.nfs_shares[var.nfs_share]
  nfs = {
    target = var.nfs_mount_target
    driver_options = {
      type   = "nfs"
      device = ":${local.nfs_selected.export}${var.nfs_subpath}"
      o      = "addr=${local.nfs_selected.server},${local.nfs_selected.options}"
    }
  }

  service_name_prefix = "gha-runner-arm64"
  nfs_volume_name     = "${local.service_name_prefix}-nfs-homelab"
  engine_build_path   = "/var/lib/gha-runner-engine-build"

  replica_indexes = { for n in range(1, local.replicas + 1) : tostring(n) => n }

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
