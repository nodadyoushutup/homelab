locals {
  service_name = "mcp-ast-grep"
  default_env = {
    TZ                                  = var.timezone
    AST_GREP_HOST                       = "0.0.0.0"
    AST_GREP_PORT                       = "8096"
    AST_GREP_DEFAULT_PROJECT_ROOT       = "/mnt/eapp/code"
    AST_GREP_ALLOWED_ROOTS              = "/mnt/eapp/code"
    AST_GREP_WORKSPACE_ROOT_HEADER      = "x-workspace-root"
    AST_GREP_WORKSPACE_ROOT_QUERY_PARAM = "workspace_root"
    MCP_HTTP_PATH                       = "/mcp"
  }
  effective_env = merge(local.default_env, var.env)
}

module "code_nfs" {
  source = "../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-code"
  target      = "/mnt/eapp/code"
  device      = var.nfs_code_device
  nfs_server  = var.nfs_server
  read_only   = true
}

module "mcp_ast_grep" {
  source = "../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "harbor.nodadyoushutup.com"
  registry_auth         = var.registry_auth
  internal_port         = 8096
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  user                  = "1000:1000"
  cap_drop              = ["ALL"]
  mounts                = [module.code_nfs.mount]
}
