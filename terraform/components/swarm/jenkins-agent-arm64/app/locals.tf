# locals.tf
# Single source of truth for Jenkins agent (ARM64) Docker values (resources read local.* only).

locals {
  agent_label_filter               = var.agent_label_filter
  agent_secrets_dir                = var.agent_secrets_dir
  casc_config_path                 = var.casc_config_path
  default_remote_fs                = var.default_remote_fs
  dns_nameservers                  = var.dns_nameservers
  enable_shared_repo_mount         = var.enable_shared_repo_mount
  engine_visible_build_path        = var.engine_visible_build_path
  env                              = var.env
  home_volume_name_prefix          = var.home_volume_name_prefix
  jenkins_url                      = var.jenkins_url
  kvm_supplementary_groups         = var.kvm_supplementary_groups
  mounts                           = var.mounts
  nfs                              = var.nfs
  service_name_prefix              = var.service_name_prefix
  shared_repo_mount_target         = var.shared_repo_mount_target
  shared_tfvars_volume_driver      = var.shared_tfvars_volume_driver
  shared_tfvars_volume_driver_opts = var.shared_tfvars_volume_driver_opts
  swarm_docker_provider_config     = var.swarm_docker_provider_config

  casc_config     = yamldecode(file(local.casc_config_path))
  requested_nodes = try(local.casc_config.jenkins.nodes, [])

  normalized_label_filter = toset([
    for label in local.agent_label_filter : lower(trimspace(label))
    if trimspace(label) != ""
  ])

  casc_node_definitions = {
    for node in local.requested_nodes : trimspace(tostring(node.permanent.name)) => {
      name      = trimspace(tostring(node.permanent.name))
      safe_name = lower(replace(trimspace(tostring(node.permanent.name)), "/[^0-9A-Za-z_.-]/", "-"))
      remote_fs = trimspace(tostring(try(node.permanent.remoteFS, local.default_remote_fs)))
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
    JENKINS_SECRETS_DIR = local.agent_secrets_dir
  }
  agent_env = merge(local.default_env, local.env)
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

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
