locals {
  service_name = "mcp-kubernetes"
  default_env = {
    TZ = var.timezone
  }
  effective_env = merge(local.default_env, var.env)
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
    "/kubeconfig/config",
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
  mounts = [
    {
      type      = "bind"
      source    = var.kubeconfig_path
      target    = "/kubeconfig/config"
      read_only = true
    },
  ]
}
