locals {
  install_root_path = trimsuffix(var.harbor_install_path, "/")
  data_root_path    = trimsuffix(var.harbor_data_path, "/")
  log_root_path     = trimsuffix(var.harbor_log_path, "/")
  config_root_path  = "${local.install_root_path}/common/config"

  env_file_contents = {
    db          = trimspace(var.env_file_paths.db) != "" ? try(file(var.env_file_paths.db), "") : ""
    core        = trimspace(var.env_file_paths.core) != "" ? try(file(var.env_file_paths.core), "") : ""
    registryctl = trimspace(var.env_file_paths.registryctl) != "" ? try(file(var.env_file_paths.registryctl), "") : ""
    jobservice  = trimspace(var.env_file_paths.jobservice) != "" ? try(file(var.env_file_paths.jobservice), "") : ""
    trivy       = trimspace(var.env_file_paths.trivy) != "" ? try(file(var.env_file_paths.trivy), "") : ""
  }

  parsed_env_file_maps = {
    for env_name, content in local.env_file_contents :
    env_name => {
      for raw_line in split("\n", replace(content, "\r\n", "\n")) :
      trimspace(split("=", trimspace(raw_line))[0]) => join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line)))))
      if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
    }
  }

  effective_env = {
    db          = length(var.env.db) > 0 ? var.env.db : local.parsed_env_file_maps.db
    core        = length(var.env.core) > 0 ? var.env.core : local.parsed_env_file_maps.core
    registryctl = length(var.env.registryctl) > 0 ? var.env.registryctl : local.parsed_env_file_maps.registryctl
    jobservice  = length(var.env.jobservice) > 0 ? var.env.jobservice : local.parsed_env_file_maps.jobservice
    trivy       = length(var.env.trivy) > 0 ? var.env.trivy : local.parsed_env_file_maps.trivy
  }

  syslog_driver_defaults = {
    "syslog-address" = "tcp://127.0.0.1:${var.log_syslog_published_port}"
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
