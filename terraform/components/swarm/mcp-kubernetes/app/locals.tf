locals {
  kubeconfig_hash  = substr(filemd5(var.kubeconfig_path), 0, 12)
  kubeconfig_force = parseint(substr(local.kubeconfig_hash, 0, 8), 16)
}
