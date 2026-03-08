locals {
  legacy_default_certificate_email = "admin@nodadyoushutup.com"

  legacy_default_dns_challenge = {
    enabled             = true
    provider            = "cloudflare"
    credentials         = var.dns_provider_credentials
    propagation_seconds = 60
  }

  legacy_certificates = [
    {
      name         = "nodadyoushutup"
      domain_names = ["nodadyoushutup.com", "www.nodadyoushutup.com"]
    },
    {
      name         = "irc"
      domain_names = ["irc.nodadyoushutup.com"]
    },
    {
      name         = "nginx_proxy_manager"
      domain_names = ["nginx-proxy-manager.nodadyoushutup.com"]
    },
    {
      name         = "dozzle"
      domain_names = ["dozzle.nodadyoushutup.com"]
    },
    {
      name         = "grafana"
      domain_names = ["grafana.nodadyoushutup.com"]
    },
    {
      name         = "minio"
      domain_names = ["minio.nodadyoushutup.com"]
    },
    {
      name         = "prometheus"
      domain_names = ["prometheus.nodadyoushutup.com"]
    },
    {
      name         = "tautulli"
      domain_names = ["tautulli.nodadyoushutup.com"]
    },
    {
      name         = "graphite"
      domain_names = ["graphite.nodadyoushutup.com"]
    },
  ]

  legacy_proxy_hosts = [
    {
      name         = "nodadyoushutup"
      domain_names = ["nodadyoushutup.com", "www.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.100"
      forward_port = 9055
      certificate  = "nodadyoushutup"
    },
    {
      name         = "irc"
      domain_names = ["irc.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.100"
      forward_port = 9009
      certificate  = "irc"
    },
    {
      name         = "nginx_proxy_manager"
      domain_names = ["nginx-proxy-manager.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.26"
      forward_port = 81
      certificate  = "nginx_proxy_manager"
    },
    {
      name         = "dozzle_nodadyoushutup_com"
      domain_names = ["dozzle.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.26"
      forward_port = 8888
      certificate  = "dozzle"
    },
    {
      name         = "grafana_nodadyoushutup_com"
      domain_names = ["grafana.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.26"
      forward_port = 3000
      certificate  = "grafana"
    },
    {
      name         = "minio_nodadyoushutup_com"
      domain_names = ["minio.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.26"
      forward_port = 9001
      certificate  = "minio"
    },
    {
      name         = "prometheus_nodadyoushutup_com"
      domain_names = ["prometheus.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.26"
      forward_port = 9090
      certificate  = "prometheus"
    },
    {
      name         = "tautulli_nodadyoushutup_com"
      domain_names = ["tautulli.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.100"
      forward_port = 9181
      certificate  = "tautulli"
    },
    {
      name         = "graphite_nodadyoushutup_com"
      domain_names = ["graphite.nodadyoushutup.com"]
      scheme       = "http"
      forward_host = "192.168.1.26"
      forward_port = 8081
      certificate  = "graphite"
    },
  ]

  legacy_config = {
    default_certificate_email = local.legacy_default_certificate_email
    default_dns_challenge     = local.legacy_default_dns_challenge
    certificates              = local.legacy_certificates
    proxy_hosts               = local.legacy_proxy_hosts
    access_lists              = []
    streams                   = []
    redirections              = []
  }

  effective_config = jsondecode(var.config != null ? jsonencode(var.config) : jsonencode(local.legacy_config))

  app_state = var.remote_state_backend == null ? null : try(data.terraform_remote_state.app[0].outputs, null)
}

data "terraform_remote_state" "app" {
  count   = var.remote_state_backend == null ? 0 : 1
  backend = "s3"
  config = merge(var.remote_state_backend, {
    key = "nginx-proxy-manager-app.tfstate"
  })
}

module "nginx_proxy_manager_config" {
  source = "../../../module/nginx_proxy_manager/config"

  provider_config = var.provider_config
  config          = local.effective_config
  app_state       = local.app_state
}
