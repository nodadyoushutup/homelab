locals {
  prometheus_config_hash  = substr(filemd5(var.prometheus_config_path), 0, 12)
  prometheus_force_update = parseint(substr(local.prometheus_config_hash, 0, 8), 16)
}
