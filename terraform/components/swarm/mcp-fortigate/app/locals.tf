# locals.tf
# Single source of truth for mcp-fortigate Swarm service values (resources read local.* only).

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

  service_name  = "mcp-fortigate"
  network_name  = "mcp-fortigate"
  network_alias = "mcp-fortigate"

  service_port = {
    target_port    = 8814
    published_port = 18205
    protocol       = "tcp"
    publish_mode   = "ingress"
  }

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
