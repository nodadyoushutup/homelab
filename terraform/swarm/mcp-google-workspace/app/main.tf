locals {
  service_name = "mcp-google-workspace"

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  parsed_env = {
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) :
    trimspace(split("=", trimspace(raw_line))[0]) => join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line)))))
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  }
  default_env = {
    TZ                                 = var.timezone
    MCP_GOOGLE_WORKSPACE_LISTEN_PORT   = "8086"
    WORKSPACE_MCP_SERVICE_ACCOUNT_FILE = var.service_account_container_path
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)
}

module "config_nfs" {
  source = "../../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-config"
  target      = "/mnt/eapp/config"
  device      = var.nfs_config_device
  nfs_server  = var.nfs_server
  read_only   = true
}

module "mcp_google_workspace" {
  source = "../../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "harbor.nodadyoushutup.com"
  registry_auths        = local.docker_registry_auths
  internal_port         = 8086
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  user                  = "1000:1000"
  cap_drop              = ["ALL"]
  mounts                = [module.config_nfs.mount]
}
