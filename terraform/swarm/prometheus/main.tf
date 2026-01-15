module "prometheus_app" {
  source = "../../module/prometheus"

  provider_config = var.provider_config
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
  targets         = var.targets
}
