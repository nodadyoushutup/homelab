data "terraform_remote_state" "app" {
  backend = "s3"
  config = merge(
    var.remote_state_backend,
    {
      key = "nginx-proxy-manager-app.tfstate"
    },
  )
}

locals {
  config = {
    default_certificate_email = var.default_certificate_email
    default_dns_challenge     = var.default_dns_challenge
    certificates              = var.certificates
    proxy_hosts               = var.proxy_hosts
    access_lists              = var.access_lists
    streams                   = var.streams
    redirections              = var.redirections
  }
}

module "nginx_proxy_manager_config" {
  source = "../../../module/nginx_proxy_manager/config"

  provider_config = var.provider_config
  config          = local.config
  app_state       = data.terraform_remote_state.app.outputs
}
