resource "nginxproxymanager_certificate_letsencrypt" "nodadyoushutup" {
  domain_names             = ["nodadyoushutup.com", "www.nodadyoushutup.com"]
  letsencrypt_email        = "admin@nodadyoushutup.com"
  letsencrypt_agree        = true
  dns_challenge            = true
  dns_provider             = "cloudflare"
  dns_provider_credentials = var.dns_provider_credentials
  propagation_seconds      = 60
}

resource "nginxproxymanager_certificate_letsencrypt" "irc" {
  domain_names             = ["irc.nodadyoushutup.com"]
  letsencrypt_email        = "admin@nodadyoushutup.com"
  letsencrypt_agree        = true
  dns_challenge            = true
  dns_provider             = "cloudflare"
  dns_provider_credentials = var.dns_provider_credentials
  propagation_seconds      = 60
}

resource "nginxproxymanager_certificate_letsencrypt" "nginx_proxy_manager" {
  domain_names             = ["nginx-proxy-manager.nodadyoushutup.com"]
  letsencrypt_email        = "admin@nodadyoushutup.com"
  letsencrypt_agree        = true
  dns_challenge            = true
  dns_provider             = "cloudflare"
  dns_provider_credentials = var.dns_provider_credentials
  propagation_seconds      = 60
}

resource "nginxproxymanager_certificate_letsencrypt" "dozzle" {
  domain_names             = ["dozzle.nodadyoushutup.com"]
  letsencrypt_email        = "admin@nodadyoushutup.com"
  letsencrypt_agree        = true
  dns_challenge            = true
  dns_provider             = "cloudflare"
  dns_provider_credentials = var.dns_provider_credentials
  propagation_seconds      = 60
}

# resource "nginxproxymanager_certificate_letsencrypt" "grafana" {
#   domain_names             = toset(["grafana.nodadyoushutup.com"])
#   letsencrypt_email        = var.certificate_dns_challenges.grafana.email_address
#   letsencrypt_agree        = true
#   dns_challenge            = var.certificate_dns_challenges.grafana.dns_challenge
#   dns_provider             = var.certificate_dns_challenges.grafana.dns_provider
#   dns_provider_credentials = local.normalized_dns_credentials.grafana
#   propagation_seconds      = var.certificate_dns_challenges.grafana.propagation_seconds
# }

# resource "nginxproxymanager_certificate_letsencrypt" "minio" {
#   domain_names             = toset(["minio.nodadyoushutup.com"])
#   letsencrypt_email        = var.certificate_dns_challenges.minio.email_address
#   letsencrypt_agree        = true
#   dns_challenge            = var.certificate_dns_challenges.minio.dns_challenge
#   dns_provider             = var.certificate_dns_challenges.minio.dns_provider
#   dns_provider_credentials = local.normalized_dns_credentials.minio
#   propagation_seconds      = var.certificate_dns_challenges.minio.propagation_seconds
# }

# resource "nginxproxymanager_certificate_letsencrypt" "prometheus" {
#   domain_names             = toset(["prometheus.nodadyoushutup.com"])
#   letsencrypt_email        = var.certificate_dns_challenges.prometheus.email_address
#   letsencrypt_agree        = true
#   dns_challenge            = var.certificate_dns_challenges.prometheus.dns_challenge
#   dns_provider             = var.certificate_dns_challenges.prometheus.dns_provider
#   dns_provider_credentials = local.normalized_dns_credentials.prometheus
#   propagation_seconds      = var.certificate_dns_challenges.prometheus.propagation_seconds
# }

# resource "nginxproxymanager_certificate_letsencrypt" "graphite" {
#   domain_names             = toset(["graphite.nodadyoushutup.com"])
#   letsencrypt_email        = var.certificate_dns_challenges.graphite.email_address
#   letsencrypt_agree        = true
#   dns_challenge            = var.certificate_dns_challenges.graphite.dns_challenge
#   dns_provider             = var.certificate_dns_challenges.graphite.dns_provider
#   dns_provider_credentials = local.normalized_dns_credentials.graphite
#   propagation_seconds      = var.certificate_dns_challenges.graphite.propagation_seconds
# }



# resource "nginxproxymanager_certificate_letsencrypt" "tautulli" {
#   domain_names             = toset(["tautulli.nodadyoushutup.com"])
#   letsencrypt_email        = var.certificate_dns_challenges.tautulli.email_address
#   letsencrypt_agree        = true
#   dns_challenge            = var.certificate_dns_challenges.tautulli.dns_challenge
#   dns_provider             = var.certificate_dns_challenges.tautulli.dns_provider
#   dns_provider_credentials = local.normalized_dns_credentials.tautulli
#   propagation_seconds      = var.certificate_dns_challenges.tautulli.propagation_seconds
# }

resource "nginxproxymanager_proxy_host" "nodadyoushutup" {
  domain_names            = ["nodadyoushutup.com", "www.nodadyoushutup.com"]
  forward_scheme          = "http"
  forward_host            = "192.168.1.100"
  forward_port            = 9055
  certificate_id          = nginxproxymanager_certificate_letsencrypt.nodadyoushutup.id
  block_exploits          = true
  ssl_forced              = true
  caching_enabled         = false
  allow_websocket_upgrade = true
  http2_support           = true
  hsts_enabled            = false
  hsts_subdomains         = false
}

resource "nginxproxymanager_proxy_host" "irc" {
  domain_names            = ["irc.nodadyoushutup.com"]
  forward_scheme          = "http"
  forward_host            = "192.168.1.100"
  forward_port            = 9009
  certificate_id          = nginxproxymanager_certificate_letsencrypt.irc.id
  block_exploits          = true
  ssl_forced              = true
  caching_enabled         = false
  allow_websocket_upgrade = true
  http2_support           = true
  hsts_enabled            = false
  hsts_subdomains         = false
}

resource "nginxproxymanager_proxy_host" "nginx_proxy_manager" {
  domain_names            = ["nginx-proxy-manager.nodadyoushutup.com"]
  forward_scheme          = "http"
  forward_host            = "192.168.1.26"
  forward_port            = 81
  certificate_id          = nginxproxymanager_certificate_letsencrypt.nginx_proxy_manager.id
  block_exploits          = true
  ssl_forced              = true
  caching_enabled         = false
  allow_websocket_upgrade = true
  http2_support           = true
  hsts_enabled            = false
  hsts_subdomains         = false
}

resource "nginxproxymanager_proxy_host" "dozzle_nodadyoushutup_com" {
  domain_names            = ["dozzle.nodadyoushutup.com"]
  forward_scheme          = "http"
  forward_host            = "192.168.1.26"
  forward_port            = 8888
  certificate_id          = nginxproxymanager_certificate_letsencrypt.dozzle.id
  block_exploits          = true
  ssl_forced              = true
  caching_enabled         = false
  allow_websocket_upgrade = true
  http2_support           = true
  hsts_enabled            = false
  hsts_subdomains         = false
}

# resource "nginxproxymanager_proxy_host" "grafana_nodadyoushutup_com" {
#   domain_names            = toset(["grafana.nodadyoushutup.com"])
#   forward_scheme          = "http"
#   forward_host            = "swarm-cp-0.internal"
#   forward_port            = 3000
#   certificate_id          = nginxproxymanager_certificate_letsencrypt.grafana.id
#   block_exploits          = true
#   ssl_forced              = true
#   caching_enabled         = false
#   allow_websocket_upgrade = true
#   http2_support           = true
#   hsts_enabled            = false
#   hsts_subdomains         = false
# }

# resource "nginxproxymanager_proxy_host" "minio_nodadyoushutup_com" {
#   domain_names            = toset(["minio.nodadyoushutup.com"])
#   forward_scheme          = "http"
#   forward_host            = "swarm-cp-0.internal"
#   forward_port            = 9001
#   certificate_id          = nginxproxymanager_certificate_letsencrypt.minio.id
#   block_exploits          = true
#   ssl_forced              = true
#   caching_enabled         = false
#   allow_websocket_upgrade = true
#   http2_support           = true
#   hsts_enabled            = false
#   hsts_subdomains         = false
# }

# resource "nginxproxymanager_proxy_host" "prometheus_nodadyoushutup_com" {
#   domain_names            = toset(["prometheus.nodadyoushutup.com"])
#   forward_scheme          = "http"
#   forward_host            = "swarm-cp-0.internal"
#   forward_port            = 9090
#   certificate_id          = nginxproxymanager_certificate_letsencrypt.prometheus.id
#   block_exploits          = true
#   ssl_forced              = true
#   caching_enabled         = false
#   allow_websocket_upgrade = true
#   http2_support           = true
#   hsts_enabled            = false
#   hsts_subdomains         = false
# }

# resource "nginxproxymanager_proxy_host" "graphite_nodadyoushutup_com" {
#   domain_names            = toset(["graphite.nodadyoushutup.com"])
#   forward_scheme          = "http"
#   forward_host            = "swarm-cp-0.internal"
#   forward_port            = 8081
#   certificate_id          = nginxproxymanager_certificate_letsencrypt.graphite.id
#   block_exploits          = true
#   ssl_forced              = true
#   caching_enabled         = false
#   allow_websocket_upgrade = true
#   http2_support           = true
#   hsts_enabled            = false
#   hsts_subdomains         = false
# }





# resource "nginxproxymanager_proxy_host" "tautulli_nodadyoushutup_com" {
#   domain_names            = toset(["tautulli.nodadyoushutup.com"])
#   forward_scheme          = "http"
#   forward_host            = "truenas.internal"
#   forward_port            = 9181
#   certificate_id          = nginxproxymanager_certificate_letsencrypt.tautulli.id
#   block_exploits          = true
#   ssl_forced              = true
#   caching_enabled         = false
#   allow_websocket_upgrade = true
#   http2_support           = true
#   hsts_enabled            = false
#   hsts_subdomains         = false
# }
