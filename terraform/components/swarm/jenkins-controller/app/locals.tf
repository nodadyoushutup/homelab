locals {
  casc_hash = substr(sha256(file(var.casc_config_path)), 0, 12)

  config_force_update = parseint(substr(local.casc_hash, 0, 8), 16)
  default_env = {
    CASC_JENKINS_CONFIG = var.casc_config_container_path
    SECRETS_DIR         = var.agent_secrets_dir
  }
  controller_env = merge(local.default_env, var.env)
  extra_mounts_by_name = {
    for mount in var.mounts : mount.name => mount
  }

  nfs_device       = trimspace(var.nfs.device)
  nfs_volume_type  = trimspace(var.nfs.volume.type)
  nfs_volume_opts  = trimspace(var.nfs.volume.opts)
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

  repo_mount_enabled = local.nfs_ready && var.enable_shared_repo_mount
  repo_mount_target  = local.repo_mount_enabled ? local.nfs_mount_target : var.shared_repo_mount_target
  shared_repo_volume_driver_opts_effective = coalesce(
    var.shared_tfvars_volume_driver_opts,
    local.repo_mount_enabled ? local.nfs_driver_opts : null
  )
  enable_shared_repo_mount_effective = var.enable_shared_repo_mount && local.shared_repo_volume_driver_opts_effective != null

  pull_ref                      = var.controller_image
  pull_at_stripped              = split("@", local.pull_ref)[0]
  pull_colon_parts              = split(":", local.pull_at_stripped)
  pull_image_repository         = length(local.pull_colon_parts) <= 1 ? local.pull_at_stripped : join(":", slice(local.pull_colon_parts, 0, length(local.pull_colon_parts) - 1))
  pull_repo_slash_parts         = split("/", local.pull_image_repository)
  pull_registry_host            = length(local.pull_repo_slash_parts) >= 2 && (strcontains(local.pull_repo_slash_parts[0], ".") || strcontains(local.pull_repo_slash_parts[0], ":") || lower(local.pull_repo_slash_parts[0]) == "localhost") ? local.pull_repo_slash_parts[0] : "docker.io"
  pull_normalized_registry_host = lower(trimspace(local.pull_registry_host))
  pull_auth_matches = [
    for a in coalesce(try(var.swarm_docker_provider_config.registry_auths, null), []) : a
    if lower(trimspace(replace(replace(try(a.address, "ghcr.io"), "https://", ""), "http://", ""))) == local.pull_normalized_registry_host
  ]
  pull_selected_auth = length(local.pull_auth_matches) > 0 ? local.pull_auth_matches[0] : (
    length(coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])) == 1 ? coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])[0] : null
  )
  pull_server_address = local.pull_selected_auth == null ? "" : trimspace(replace(replace(try(local.pull_selected_auth.address, "ghcr.io"), "https://", ""), "http://", ""))
  docker_service_pull_auth_map = local.pull_selected_auth == null ? {} : {
    pull = {
      server_address = local.pull_server_address
      username       = local.pull_selected_auth.username
      password       = local.pull_selected_auth.password
    }
  }
}
