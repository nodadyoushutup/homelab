# locals.tf
# Single source of truth for Nginx Proxy Manager config slice values (resources read local.* only).

locals {
  provider_config = var.provider_config
  default         = var.default
  certificates    = var.certificates
  access_lists    = var.access_lists
  proxy_hosts     = var.proxy_hosts
  redirections    = var.redirections
  streams         = var.streams

  advanced_config_file   = "${path.module}/files/advanced.conf"
  default_site_html_file = "${path.module}/files/404.html"
}
