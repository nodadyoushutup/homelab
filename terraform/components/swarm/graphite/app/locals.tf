# locals.tf
# Single source of truth for Graphite Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "graphite"
  network_name  = "graphite-net"
  network_alias = "graphite"

  volume_name          = "graphite-data"
  storage_mount_target = "/opt/graphite/storage"

  replicas = 1

  ports = [
    { target_port = 8080, published_port = 8081, protocol = "tcp", publish_mode = "ingress" },
    { target_port = 2003, published_port = 2003, protocol = "tcp", publish_mode = "ingress" },
    { target_port = 2003, published_port = 2003, protocol = "udp", publish_mode = "ingress" },
    { target_port = 2004, published_port = 2004, protocol = "tcp", publish_mode = "ingress" },
    { target_port = 8125, published_port = 8125, protocol = "udp", publish_mode = "ingress" },
  ]

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
