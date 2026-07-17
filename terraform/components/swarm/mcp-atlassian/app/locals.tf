# locals.tf
# Single source of truth for mcp-atlassian Swarm service values (resources read local.* only).

locals {
  env                          = var.env
  replicas                     = var.replicas
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "mcp-atlassian"
  network_name  = "mcp-atlassian"
  network_alias = "mcp-atlassian"

  service_port = {
    target_port    = 8000
    published_port = 18200
    protocol       = "tcp"
    publish_mode   = "ingress"
  }

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
