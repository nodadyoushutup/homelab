locals {
  telegraf_config_hash  = substr(filemd5("${path.module}/telegraf.conf"), 0, 12)
  telegraf_force_update = parseint(substr(local.telegraf_config_hash, 0, 8), 16)
}
