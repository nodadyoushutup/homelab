module "graphite" {
  source = "../../../module/graphite"

  provider_config = var.provider_config
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
}
