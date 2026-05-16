locals {
  service_name = "mcp-kubernetes"
  default_env = {
    TZ = var.timezone
  }
  effective_env = merge(local.default_env, var.env)

  swarm_nfs_ready = (
    trimspace(var.swarm_nfs_code_device) != "" &&
    trimspace(var.swarm_nfs_config_device) != "" &&
    trimspace(var.swarm_nfs_volume_type) != "" &&
    trimspace(var.swarm_nfs_volume_o_rw) != "" &&
    trimspace(var.swarm_nfs_volume_o_ro) != ""
  )
  swarm_nfs_config_target = trimspace(element(split(":", trimspace(var.swarm_nfs_config_device)), length(split(":", trimspace(var.swarm_nfs_config_device))) - 1))

  kubeconfig_container_path = "${local.swarm_nfs_config_target}/mcp-kubernetes/kubeconfig"

  swarm_nfs_config_mounts = local.swarm_nfs_ready ? [{
    type      = "volume"
    source    = "${local.service_name}-mnt-eapp-config"
    target    = local.swarm_nfs_config_target
    read_only = true
    volume_options = {
      driver_name = "local"
      driver_options = {
        type   = trimspace(var.swarm_nfs_volume_type)
        o      = trimspace(var.swarm_nfs_volume_o_ro)
        device = trimspace(var.swarm_nfs_config_device)
      }
      no_copy = false
    }
  }] : []
}


locals {
  pull_ref                      = var.image_reference
  pull_at_stripped              = split("@", local.pull_ref)[0]
  pull_colon_parts              = split(":", local.pull_at_stripped)
  pull_image_repository         = length(local.pull_colon_parts) <= 1 ? local.pull_at_stripped : join(":", slice(local.pull_colon_parts, 0, length(local.pull_colon_parts) - 1))
  pull_repo_slash_parts         = split("/", local.pull_image_repository)
  pull_registry_host            = length(local.pull_repo_slash_parts) >= 2 && (strcontains(local.pull_repo_slash_parts[0], ".") || strcontains(local.pull_repo_slash_parts[0], ":") || lower(local.pull_repo_slash_parts[0]) == "localhost") ? local.pull_repo_slash_parts[0] : "docker.io"
  pull_normalized_registry_host = lower(trimspace(local.pull_registry_host))
  pull_auth_matches = [
    for a in local.docker_registry_auths : a
    if lower(trimspace(replace(replace(try(a.address, "ghcr.io"), "https://", ""), "http://", ""))) == local.pull_normalized_registry_host
  ]
  pull_selected_auth = length(local.pull_auth_matches) > 0 ? local.pull_auth_matches[0] : (
    length(local.docker_registry_auths) == 1 ? local.docker_registry_auths[0] : null
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

locals {
  provider_config = merge(var.swarm_docker_provider_config, var.provider_config)
  docker_registry_auths = (
    try(local.provider_config.registry_auths, null) != null
    ? local.provider_config.registry_auths
    : (
      try(local.provider_config.registry_auth, null) != null
      ? [local.provider_config.registry_auth]
      : []
    )
  )
}
