locals {
  service_name = "mcp-bash-pipeline"
  default_env = {
    TZ                                    = var.timezone
    BASH_PIPELINE_PORT                    = "8107"
    BASH_PIPELINE_HTTP_PATH               = "/mcp"
    BASH_PIPELINE_DEFAULT_WORKSPACE_ROOT  = "/mnt/eapp/code/homelab"
    BASH_PIPELINE_ALLOWED_WORKSPACE_ROOTS = "/mnt/eapp/code"
    BASH_PIPELINE_CONFIG_ROOT             = "/mnt/eapp/config"
    BASH_PIPELINE_WORKSPACE_ROOT_HEADER   = "x-workspace-root"
    BASH_PIPELINE_WORKSPACE_NAME_HEADER   = "x-homelab-workspace"
    BASH_PIPELINE_DEFAULT_WORKSPACE_NAME  = "homelab"
    BASH_PIPELINE_DEFAULT_TIMEOUT_SECONDS = "1800"
    BASH_PIPELINE_MAX_OUTPUT_CHARS        = "12000"
  }
  effective_env = merge(local.default_env, var.env)
}

module "code_nfs" {
  source = "../../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-code"
  target      = "/mnt/eapp/code"
  device      = var.nfs_code_device
  nfs_server  = var.nfs_server
  read_only   = false
}

module "config_nfs" {
  source = "../../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-config"
  target      = "/mnt/eapp/config"
  device      = var.nfs_config_device
  nfs_server  = var.nfs_server
  read_only   = false
}

module "mcp_bash_pipeline" {
  source = "../../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "harbor.nodadyoushutup.com"
  registry_auth         = var.registry_auth
  internal_port         = 8107
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  user                  = "1000:1000"
  cap_drop              = ["ALL"]
  mounts = [
    module.code_nfs.mount,
    module.config_nfs.mount,
  ]
}
