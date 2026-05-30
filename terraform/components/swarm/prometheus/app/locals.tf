locals {
  config_hash  = substr(filemd5(var.config_path), 0, 12)
  force_update = parseint(substr(local.config_hash, 0, 8), 16)
}
