locals {
  npm_provider = var.provider_config.nginx_proxy_manager

  provider_username = local.npm_provider.username
  provider_password = try(local.npm_provider.password, null)

  certificates = {
    for cert in coalesce(var.config.certificates, []) : cert.name => cert
  }

  proxy_hosts = {
    for host in coalesce(var.config.proxy_hosts, []) : host.name => host
  }

  access_lists = {
    for list in coalesce(var.config.access_lists, []) : list.name => list
  }

  stack_namespace = coalesce(
    try(var.app_state.stack_name, null),
    "nginx-proxy-manager",
  )

  default_certificate_email = try(var.config.default_certificate_email, null)

  default_dns_challenge = {
    enabled             = try(var.config.default_dns_challenge.enabled, null)
    provider            = try(var.config.default_dns_challenge.provider, null)
    credentials         = try(var.config.default_dns_challenge.credentials, null)
    propagation_seconds = try(var.config.default_dns_challenge.propagation_seconds, null)
  }

  certificate_dns_settings = {
    for name, cert in local.certificates : name => {
      provider = (
        try(cert.dns_provider, null) != null
        ? cert.dns_provider
        : local.default_dns_challenge.provider
      )
      credentials = (
        try(cert.dns_provider_credentials, null) != null
        ? cert.dns_provider_credentials
        : local.default_dns_challenge.credentials
      )
    }
  }

  normalized_dns_credentials = {
    for name, settings in local.certificate_dns_settings : name => (
      settings.credentials == null
      ? null
      : (
        settings.provider != null &&
        can(regex("cloudflare", lower(settings.provider))) &&
        !can(regex("=", settings.credentials))
        ? format("dns_cloudflare_api_token = %s", settings.credentials)
        : settings.credentials
      )
    )
  }
}

provider "nginxproxymanager" {
  url      = local.npm_provider.url
  username = local.provider_username
  password = local.provider_password
}

resource "nginxproxymanager_access_list" "this" {
  for_each = local.access_lists

  name        = each.value.name
  pass_auth   = try(each.value.pass_auth, true)
  satisfy_any = try(each.value.satisfy_any, false)

  authorizations = [
    for item in coalesce(each.value.authorizations, []) : {
      username = item.username
      password = item.password
    }
  ]

  access = [
    for rule in coalesce(each.value.access, []) : {
      directive = rule.directive
      address   = rule.address
    }
  ]
}

resource "nginxproxymanager_certificate_letsencrypt" "this" {
  for_each = {
    for name, cert in local.certificates : name => cert
    if try(cert.request_le, true)
  }

  domain_names = toset(each.value.domain_names)
  letsencrypt_email = coalesce(
    try(each.value.email_address, null),
    local.default_certificate_email,
  )
  letsencrypt_agree = true

  dns_challenge = coalesce(
    try(each.value.dns_challenge, null),
    local.default_dns_challenge.enabled,
    false,
  )

  dns_provider = (
    try(each.value.dns_provider, null) != null
    ? each.value.dns_provider
    : local.default_dns_challenge.provider
  )

  dns_provider_credentials = local.normalized_dns_credentials[each.key]

  propagation_seconds = (
    try(each.value.propagation_seconds, null) != null
    ? each.value.propagation_seconds
    : local.default_dns_challenge.propagation_seconds
  )
}

locals {
  certificate_ids = {
    for name, cert in nginxproxymanager_certificate_letsencrypt.this : name => cert.id
  }

  access_list_ids = {
    for name, acl in nginxproxymanager_access_list.this : name => acl.id
  }
}

resource "nginxproxymanager_proxy_host" "this" {
  for_each = local.proxy_hosts

  domain_names   = toset(each.value.domain_names)
  forward_scheme = lower(each.value.scheme)
  forward_host   = each.value.forward_host
  forward_port   = each.value.forward_port

  block_exploits          = try(each.value.block_exploits, true)
  ssl_forced              = try(each.value.ssl_forced, true)
  caching_enabled         = try(each.value.caching_enabled, false)
  allow_websocket_upgrade = try(each.value.allow_websocket_upgrade, true)
  http2_support           = try(each.value.http2_support, true)
  hsts_enabled            = try(each.value.hsts_enabled, false)
  hsts_subdomains         = try(each.value.hsts_subdomains, false)
  advanced_config         = try(each.value.advanced_config, null)

  access_list_id = (
    try(each.value.access_list_id, null) != null
    ? each.value.access_list_id
    : (
      try(each.value.access_list, null) != null
      ? lookup(local.access_list_ids, each.value.access_list, null)
      : null
    )
  )

  certificate_id = (
    try(each.value.certificate, null) != null
    ? lookup(local.certificate_ids, each.value.certificate, null)
    : null
  )

  locations = [
    for location in coalesce(each.value.locations, []) : {
      path            = location.path
      forward_scheme  = lower(location.scheme)
      forward_host    = location.forward_host
      forward_port    = location.forward_port
      advanced_config = try(location.advanced_config, null)
    }
  ]
}
