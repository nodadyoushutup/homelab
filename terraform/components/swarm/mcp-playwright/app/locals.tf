# locals.tf
# Single source of truth for mcp-playwright Swarm service values (resources read local.* only).

locals {
  env             = var.env
  replicas        = var.replicas
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
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

  service_name  = "mcp-playwright"
  network_name  = "mcp-playwright"
  network_alias = "mcp-playwright"

  args = [
    "--headless",
    "--browser", "chromium",
    "--no-sandbox",
    "--viewport-size", "1920x1080",
    "--port", "8931",
    "--host", "0.0.0.0",
    "--allowed-hosts", "*",
  ]

  nfs_volume_source = "mcp-playwright-nfs"

  service_port = {
    target_port    = 8931
    published_port = 18211
    protocol       = "tcp"
    publish_mode   = "ingress"
  }

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
