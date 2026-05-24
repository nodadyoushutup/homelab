locals {
  install_root_path = trimsuffix(var.harbor_install_path, "/")
  data_root_path    = trimsuffix(var.harbor_data_path, "/")
  log_root_path     = trimsuffix(var.harbor_log_path, "/")
  config_root_path  = "${local.install_root_path}/common/config"

  component_env_paths = {
    db          = "${local.config_root_path}/db/env"
    core        = "${local.config_root_path}/core/env"
    registryctl = "${local.config_root_path}/registryctl/env"
    jobservice  = "${local.config_root_path}/jobservice/env"
    trivy       = "${local.config_root_path}/trivy-adapter/env"
  }

  env_file_contents = {
    for env_name, env_path in local.component_env_paths :
    env_name => try(file(env_path), "")
  }

  parsed_env_file_maps = {
    for env_name, content in local.env_file_contents :
    env_name => {
      for raw_line in split("\n", replace(content, "\r\n", "\n")) :
      trimspace(split("=", trimspace(raw_line))[0]) => join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line)))))
      if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
    }
  }

  effective_env = local.parsed_env_file_maps

  syslog_driver_defaults = {
    "syslog-address" = "tcp://127.0.0.1:${var.log_syslog_published_port}"
  }
}
