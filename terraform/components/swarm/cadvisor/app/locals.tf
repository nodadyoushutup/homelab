# locals.tf
# Single source of truth for cAdvisor Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "cadvisor"
  network_name  = "cadvisor"
  network_alias = "cadvisor"

  args = [
    "--docker=unix:///var/run/docker.sock",
    "--docker_only=true",
    "--store_container_labels=false",
    "--whitelisted_container_labels=com.docker.swarm.service.name,com.docker.swarm.task.name,com.docker.swarm.node.id",
  ]

  metrics_port = 8080

  # Host binds required for cgroup / Docker introspection (not app source).
  mounts = [
    {
      target    = "/rootfs"
      source    = "/"
      type      = "bind"
      read_only = true
    },
    {
      target    = "/var/run/docker.sock"
      source    = "/var/run/docker.sock"
      type      = "bind"
      read_only = false
    },
    {
      target    = "/var/run"
      source    = "/var/run"
      type      = "bind"
      read_only = true
    },
    {
      target    = "/sys"
      source    = "/sys"
      type      = "bind"
      read_only = true
    },
    {
      target    = "/var/lib/docker"
      source    = "/var/lib/docker"
      type      = "bind"
      read_only = true
    },
    {
      target    = "/dev/disk"
      source    = "/dev/disk"
      type      = "bind"
      read_only = true
    },
  ]

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
