locals {
  service_name = "mcp-git"
  default_env = {
    TZ                      = var.timezone
    MCP_GIT_REPOSITORY_ROOT = "/mnt/eapp/code/homelab"
    MCP_GIT_LISTEN_PORT     = "8099"
  }
  effective_env = merge(local.default_env, var.env)
}

module "code_nfs" {
  source = "../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-code"
  target      = "/mnt/eapp/code"
  device      = var.nfs_code_device
  nfs_server  = var.nfs_server
  read_only   = false
}

module "mcp_git" {
  source = "../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "harbor.nodadyoushutup.com"
  registry_auth         = var.registry_auth
  internal_port         = 8099
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
