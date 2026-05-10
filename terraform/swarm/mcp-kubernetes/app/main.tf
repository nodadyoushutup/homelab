locals {
  service_name = "mcp-kubernetes"
  default_env = {
    TZ = var.timezone
  }
  effective_env = merge(local.default_env, var.env)

  kubeconfig_container_path = "/mnt/eapp/config/mcp-kubernetes/kubeconfig"
}

module "config_nfs" {
  source = "../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-config"
  target      = "/mnt/eapp/config"
  device      = var.nfs_config_device
  nfs_server  = var.nfs_server
  read_only   = true
}

module "mcp_kubernetes" {
  source = "../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "quay.io"
  registry_auth         = var.registry_auth
  internal_port         = 8106
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  user                  = "65532"
  cap_drop              = ["ALL"]
  args = [
    "--port",
    "8106",
    "--kubeconfig",
    local.kubeconfig_container_path,
    "--cluster-provider",
    "kubeconfig",
    "--toolsets",
    "core,config",
    "--list-output",
    "yaml",
    "--read-only",
    "--disable-multi-cluster",
    "--stateless",
  ]
  mounts = [module.config_nfs.mount]
}
