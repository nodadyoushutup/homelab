locals {
  service_name = "mcp-atlassian"

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  parsed_env = {
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) :
    trimspace(split("=", trimspace(raw_line))[0]) => join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line)))))
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  }
  default_env = {
    TZ = var.timezone
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)
}

module "code_nfs" {
  source = "../../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-code"
  target      = "/mnt/eapp/code"
  device      = var.nfs_code_device
  nfs_server  = var.nfs_server
  read_only   = false
}

module "mcp_atlassian" {
  source = "../../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "ghcr.io"
  registry_auths        = local.docker_registry_auths
  internal_port         = 8000
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  args = [
    "--transport",
    "streamable-http",
    "--host",
    "0.0.0.0",
    "--port",
    "8000",
    "--path",
    "/mcp",
    "--toolsets",
    "all",
  ]
  mounts = [module.code_nfs.mount]
}
