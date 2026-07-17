# locals.tf
# Single source of truth for Dozzle Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "dozzle"
  network_name  = "dozzle"
  network_alias = "dozzle"

  env = {
    DOZZLE_MODE = "swarm"
  }

  docker_sock_path = "/var/run/docker.sock"

  ui_port = {
    target_port    = 8080
    published_port = 8888
    publish_mode   = "ingress"
  }

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
