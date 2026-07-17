# locals.tf
# Single source of truth for mcp-playwright Swarm service values (resources read local.* only).

locals {
  env                          = var.env
  replicas                     = var.replicas
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  nfs                          = var.nfs
  swarm_docker_provider_config = var.swarm_docker_provider_config

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
