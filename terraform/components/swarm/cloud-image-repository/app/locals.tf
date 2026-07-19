# locals.tf
# Single source of truth for cloud-image-repository Swarm service values (resources read local.* only).

locals {
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

  # Compose the Docker NFS volume from the shared catalog (config-id terraform/nfs).
  # This slice serves a sub-path of the export (data/packer) and has no container
  # target of its own (mounted at local.data_mount below).
  nfs_selected = var.nfs_shares[var.nfs_share]
  nfs = {
    driver_options = {
      type   = "nfs"
      device = ":${local.nfs_selected.export}${var.nfs_subpath}"
      o      = "addr=${local.nfs_selected.server},${local.nfs_selected.options}"
    }
  }

  service_name  = "cloud-image-repository"
  network_name  = "cloud-image-repository"
  network_alias = "cloud-image-repository"
  # NFS-backed volume name (holds no local data; just points at data/packer).
  volume_name = "cloud-image-repository-packer"

  nfs_driver_options = local.nfs.driver_options

  target_port    = 8080
  published_port = 18088
  data_mount     = "/data"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
