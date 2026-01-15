module "grafana_config" {
  source = "../../../module/grafana/config"

  datasources = var.datasources
}
