locals {
  service_name = "mcp-filesystem"
  default_env = {
    TZ                            = var.timezone
    MCP_FILESYSTEM_WORKSPACE_ROOT = "/mnt/eapp/code/homelab"
    MCP_FILESYSTEM_LISTEN_PORT    = "8098"
  }
  effective_env = merge(local.default_env, var.env)
}

module "mcp_filesystem" {
  source = "../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "harbor.nodadyoushutup.com"
  registry_auth         = var.registry_auth
  internal_port         = 8098
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
    {
      type   = "bind"
      source = var.code_root_path
      target = "/mnt/eapp/code"
    },
  ]
}
