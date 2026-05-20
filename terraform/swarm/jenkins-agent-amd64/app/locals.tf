locals {
  casc_config     = yamldecode(file(var.casc_config_path))
  requested_nodes = try(local.casc_config.jenkins.nodes, [])

  normalized_label_filter = toset([
    for label in var.agent_label_filter : lower(trimspace(label))
    if trimspace(label) != ""
  ])

  casc_node_definitions = {
    for node in local.requested_nodes : trimspace(tostring(node.permanent.name)) => {
      name      = trimspace(tostring(node.permanent.name))
      safe_name = lower(replace(trimspace(tostring(node.permanent.name)), "/[^0-9A-Za-z_.-]/", "-"))
      remote_fs = trimspace(tostring(try(node.permanent.remoteFS, var.default_remote_fs)))
      label_tokens = toset([
        for token in split(" ", replace(
          trimspace(tostring(try(
            node.permanent.labelString,
            join(" ", try(node.permanent.labels, []))
          ))),
          ",",
          " "
        )) : lower(trimspace(token))
        if trimspace(token) != ""
      ])
    } if try(trimspace(tostring(node.permanent.name)) != "", false)
  }

  agent_definitions = {
    for node_name, node in local.casc_node_definitions : node_name => node
    if length(local.normalized_label_filter) == 0 || alltrue([
      for label in local.normalized_label_filter : contains(node.label_tokens, label)
    ])
  }

  default_env = {
    JENKINS_SECRETS_DIR = var.agent_secrets_dir
  }
  agent_env = merge(local.default_env, var.env)
  extra_mounts_by_name = {
    for mount in var.mounts : mount.name => mount
  }

  swarm_nfs_ready = nonsensitive(
    length(trimspace(var.swarm_nfs_code_device)) > 0 &&
    length(trimspace(var.swarm_nfs_config_device)) > 0 &&
    length(trimspace(var.swarm_nfs_volume_type)) > 0 &&
    length(trimspace(var.swarm_nfs_volume_o_rw)) > 0
  )
  swarm_nfs_code_target   = local.swarm_nfs_ready ? trimspace(element(split(":", trimspace(var.swarm_nfs_code_device)), length(split(":", trimspace(var.swarm_nfs_code_device))) - 1)) : var.shared_tfvars_mount_target
  swarm_nfs_config_target = local.swarm_nfs_ready ? trimspace(element(split(":", trimspace(var.swarm_nfs_config_device)), length(split(":", trimspace(var.swarm_nfs_config_device))) - 1)) : var.shared_tfvars_mount_target
  shared_tfvars_nfs_driver_opts_default = local.swarm_nfs_ready ? {
    type   = trimspace(var.swarm_nfs_volume_type)
    o      = trimspace(var.swarm_nfs_volume_o_rw)
    device = trimspace(var.swarm_nfs_config_device)
  } : null
  shared_tfvars_volume_driver_opts_effective = coalesce(var.shared_tfvars_volume_driver_opts, local.shared_tfvars_nfs_driver_opts_default)
  enable_shared_tfvars_mount_effective       = var.enable_shared_tfvars_mount && local.shared_tfvars_volume_driver_opts_effective != null
  jenkins_agent_nfs_volume_keys = local.swarm_nfs_ready ? toset(compact([
    var.enable_shared_tfvars_mount ? "config" : "",
    var.enable_shared_code_mount ? "code" : "",
  ])) : toset([])
  jenkins_agent_nfs_container_targets = {
    config = local.swarm_nfs_config_target
    code   = local.swarm_nfs_code_target
  }
  jenkins_agent_nfs_devices = {
    config = trimspace(var.swarm_nfs_config_device)
    code   = trimspace(var.swarm_nfs_code_device)
  }
  swarm_nfs_code_mounts = var.enable_shared_code_mount && local.swarm_nfs_ready ? [{
    type   = "volume"
    source = "${var.service_name_prefix}-mnt-eapp-code"
    target = local.swarm_nfs_code_target
    volume_options = {
      driver_name = var.shared_tfvars_volume_driver
      driver_options = {
        type   = trimspace(var.swarm_nfs_volume_type)
        o      = trimspace(var.swarm_nfs_volume_o_rw)
        device = trimspace(var.swarm_nfs_code_device)
      }
      no_copy = false
    }
  }] : []

  pull_ref                      = var.agent_image
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
  docker_registry_auths = coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])
}
