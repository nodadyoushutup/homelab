# locals.tf
# Single source of truth for zot Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  htpasswd_path                = var.htpasswd_path
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "zot"
  network_name  = "zot"
  network_alias = "zot"
  volume_name   = "zot-data"

  data_mount     = "/var/lib/registry"
  htpasswd_mount = "/etc/zot/htpasswd"
  config_mount   = "/etc/zot/config.json"
  published_port = 35081

  auth_enabled = fileexists(local.htpasswd_path)

  zot_config_raw = templatefile("${path.module}/files/zot-config.json.tpl", {
    auth_enabled = local.auth_enabled
  })
  zot_config = jsondecode(local.zot_config_raw)

  config_hash  = substr(sha256(local.zot_config_raw), 0, 8)
  force_update = parseint(substr(local.config_hash, 0, 8), 16)
  config_name  = "zot-config-${local.config_hash}"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "zot.nodadyoushutup.com"
}
