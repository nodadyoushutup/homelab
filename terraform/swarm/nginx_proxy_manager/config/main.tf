resource "nginxproxymanager_certificate_letsencrypt" "this" {
  for_each = local.certificate_specs

  domain_names      = toset(each.value.domain_names)
  letsencrypt_email = coalesce(try(each.value.letsencrypt_email, null), local.default_certificate_email)
  letsencrypt_agree = try(each.value.letsencrypt_agree, true)

  dns_challenge            = try(each.value.dns_challenge.enabled, each.value.dns_challenge, try(local.default_dns_challenge.enabled, false))
  dns_provider             = try(each.value.dns_challenge.provider, try(local.default_dns_challenge.provider, null))
  dns_provider_credentials = try(each.value.dns_challenge.credentials, try(local.default_dns_challenge.credentials, null))
  propagation_seconds      = try(each.value.dns_challenge.propagation_seconds, try(local.default_dns_challenge.propagation_seconds, null))
}

resource "nginxproxymanager_access_list" "this" {
  for_each = local.access_list_specs

  name        = each.value.name
  satisfy_any = try(each.value.satisfy_any, null)
  pass_auth   = try(each.value.pass_auth, null)
  authorizations = try([
    for auth in each.value.authorizations : {
      username = auth.username
      password = auth.password
    }
  ], null)
  access = try([
    for rule in each.value.access : {
      directive = rule.directive
      address   = rule.address
    }
  ], null)
}

resource "nginxproxymanager_proxy_host" "this" {
  for_each = local.proxy_host_specs

  domain_names   = toset(each.value.domain_names)
  forward_scheme = try(each.value.forward_scheme, each.value.scheme)
  forward_host   = each.value.forward_host
  forward_port   = tonumber(each.value.forward_port)

  certificate_id = try(
    each.value.certificate_id,
    nginxproxymanager_certificate_letsencrypt.this[each.value.certificate].id,
    null
  )

  access_list_id = try(
    each.value.access_list_id,
    nginxproxymanager_access_list.this[each.value.access_list].id,
    null
  )

  enabled                 = try(each.value.enabled, true)
  block_exploits          = try(each.value.block_exploits, true)
  caching_enabled         = try(each.value.caching_enabled, false)
  allow_websocket_upgrade = try(each.value.allow_websocket_upgrade, true)
  http2_support           = try(each.value.http2_support, true)
  ssl_forced              = try(each.value.ssl_forced, true)
  hsts_enabled            = try(each.value.hsts_enabled, false)
  hsts_subdomains         = try(each.value.hsts_subdomains, false)
  advanced_config         = try(each.value.advanced_config, "")
  locations = try([
    for location in each.value.locations : {
      path            = location.path
      forward_scheme  = try(location.forward_scheme, location.scheme)
      forward_host    = location.forward_host
      forward_port    = tonumber(location.forward_port)
      advanced_config = try(location.advanced_config, "")
    }
  ], null)
}

resource "nginxproxymanager_redirection_host" "this" {
  for_each = local.redirection_specs

  domain_names = toset(each.value.domain_names)

  forward_domain_name = try(each.value.forward_domain_name, each.value.domain_name)
  forward_scheme      = try(each.value.forward_scheme, "auto")
  forward_http_code   = try(each.value.forward_http_code, 301)
  preserve_path       = try(each.value.preserve_path, true)

  certificate_id = try(
    each.value.certificate_id,
    nginxproxymanager_certificate_letsencrypt.this[each.value.certificate].id,
    null
  )

  enabled         = try(each.value.enabled, true)
  block_exploits  = try(each.value.block_exploits, true)
  http2_support   = try(each.value.http2_support, true)
  ssl_forced      = try(each.value.ssl_forced, true)
  hsts_enabled    = try(each.value.hsts_enabled, false)
  hsts_subdomains = try(each.value.hsts_subdomains, false)
  advanced_config = try(each.value.advanced_config, "")
}

resource "nginxproxymanager_stream" "this" {
  for_each = local.stream_specs

  incoming_port   = tonumber(each.value.incoming_port)
  forwarding_host = each.value.forwarding_host
  forwarding_port = tonumber(each.value.forwarding_port)

  certificate_id = try(
    each.value.certificate_id,
    nginxproxymanager_certificate_letsencrypt.this[each.value.certificate].id,
    null
  )

  enabled        = try(each.value.enabled, true)
  tcp_forwarding = try(each.value.tcp_forwarding, true)
  udp_forwarding = try(each.value.udp_forwarding, false)
}

resource "nginxproxymanager_settings" "default_site" {
  default_site = {
    page = "html"
    html = local.default_site_404_html
  }
}
