module "grafana_app" {
  source = "../../../module/grafana/app"

  provider_config = var.provider_config
  env             = var.env
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
}
