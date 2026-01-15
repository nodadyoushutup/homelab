module "dozzle_app" {
  source = "../../../module/dozzle"

  provider_config = var.provider_config
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
}
