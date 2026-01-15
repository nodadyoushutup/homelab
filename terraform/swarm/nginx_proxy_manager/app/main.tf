module "nginx_proxy_manager_app" {
  source = "../../../module/nginx_proxy_manager/app"

  provider_config = var.provider_config
  env             = var.env
  dns_nameservers = var.dns_nameservers
  placement       = var.placement
}
