locals {
  grafana_ini_hash         = substr(filemd5(var.ini_path), 0, 12)
  grafana_ini_force_update = parseint(substr(local.grafana_ini_hash, 0, 8), 16)
}
