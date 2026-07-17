# locals.tf
# Single source of truth for node_exporter Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "node-exporter"
  network_name  = "node-exporter"
  network_alias = "node-exporter"

  args = [
    "--path.procfs=/host/proc",
    "--path.sysfs=/host/sys",
    "--path.rootfs=/host/rootfs",
    "--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($|/)",
    "--collector.filesystem.ignored-fs-types=^(autofs|proc|sysfs|tmpfs|devtmpfs|devpts|overlay|aufs)$",
  ]

  metrics_port = 9100

  # Host binds required for node metrics collection (not app source).
  mounts = [
    {
      target    = "/host/proc"
      source    = "/proc"
      type      = "bind"
      read_only = true
    },
    {
      target    = "/host/sys"
      source    = "/sys"
      type      = "bind"
      read_only = true
    },
    {
      target    = "/host/rootfs"
      source    = "/"
      type      = "bind"
      read_only = true
    },
    {
      target    = "/etc/host_hostname"
      source    = "/etc/hostname"
      type      = "bind"
      read_only = true
    },
  ]

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
