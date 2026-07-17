# locals.tf
# Single source of truth for Jenkins controller Swarm service values (resources read local.* only).

locals {
  agent_published_port             = var.agent_published_port
  agent_secrets_dir                = var.agent_secrets_dir
  agent_target_port                = var.agent_target_port
  casc_config_container_path       = var.casc_config_container_path
  casc_config_path                 = var.casc_config_path
  controller_published_port        = var.controller_published_port
  controller_replicas              = var.controller_replicas
  controller_target_port           = var.controller_target_port
  dns_nameservers                  = var.dns_nameservers
  enable_shared_repo_mount         = var.enable_shared_repo_mount
  env                              = var.env
  home_mount_target                = var.home_mount_target
  home_volume_name                 = var.home_volume_name
  mounts                           = var.mounts
  network_name                     = var.network_name
  nfs                              = var.nfs
  placement                        = var.placement
  service_dns_alias                = var.service_dns_alias
  service_name                     = var.service_name
  shared_repo_mount_target         = var.shared_repo_mount_target
  shared_tfvars_volume_driver      = var.shared_tfvars_volume_driver
  shared_tfvars_volume_driver_opts = var.shared_tfvars_volume_driver_opts
  shared_tfvars_volume_name        = var.shared_tfvars_volume_name
  swarm_docker_provider_config     = var.swarm_docker_provider_config

  casc_hash = substr(sha256(file(local.casc_config_path)), 0, 12)

  config_force_update = parseint(substr(local.casc_hash, 0, 8), 16)
  default_env = {
    CASC_JENKINS_CONFIG = local.casc_config_container_path
    SECRETS_DIR         = local.agent_secrets_dir
  }
  controller_env = merge(local.default_env, local.env)
  extra_mounts_by_name = {
    for mount in local.mounts : mount.name => mount
  }

  nfs_device       = trimspace(local.nfs.device)
  nfs_volume_type  = trimspace(local.nfs.volume.type)
  nfs_volume_opts  = trimspace(local.nfs.volume.opts)
  nfs_mount_target = local.nfs_device != "" ? trimspace(element(split(":", local.nfs_device), length(split(":", local.nfs_device)) - 1)) : ""
  nfs_driver_opts = merge({
    type = local.nfs_volume_type
    o    = local.nfs_volume_opts
  }, local.nfs_device != "" ? { device = local.nfs_device } : {})
  nfs_ready = nonsensitive(
    local.nfs_device != "" &&
    local.nfs_volume_type != "" &&
    local.nfs_volume_opts != ""
  )

  repo_mount_enabled = local.nfs_ready && local.enable_shared_repo_mount
  repo_mount_target  = local.repo_mount_enabled ? local.nfs_mount_target : local.shared_repo_mount_target
  shared_repo_volume_driver_opts_effective = coalesce(
    local.shared_tfvars_volume_driver_opts,
    local.repo_mount_enabled ? local.nfs_driver_opts : null
  )
  enable_shared_repo_mount_effective = local.enable_shared_repo_mount && local.shared_repo_volume_driver_opts_effective != null

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
