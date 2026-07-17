# locals.tf
# Single source of truth for mcp-kubernetes Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  kubeconfig_path              = var.kubeconfig_path
  placement                    = var.placement
  replicas                     = var.replicas
  swarm_docker_provider_config = var.swarm_docker_provider_config

  service_name  = "mcp-kubernetes"
  network_name  = "mcp-kubernetes"
  network_alias = "mcp-kubernetes"

  target_port      = 8106
  published_port   = 18210
  kubeconfig_mount = "/etc/kubernetes/kubeconfig"
  container_user   = "65532"
  cap_drop         = ["ALL"]

  args = [
    "--port",
    tostring(local.target_port),
    "--kubeconfig",
    local.kubeconfig_mount,
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

  kubeconfig_hash        = substr(filemd5(local.kubeconfig_path), 0, 12)
  kubeconfig_force       = parseint(substr(local.kubeconfig_hash, 0, 8), 16)
  kubeconfig_config_name = "mcp-kubernetes-kubeconfig-${local.kubeconfig_hash}"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "quay.io"
}
