locals {
  default_site_404_html = templatefile("${path.module}/default-site-404.html.tftpl", {})

  effective_config = jsondecode(jsonencode(var.config))

  default_certificate_email = try(local.effective_config.default_certificate_email, null)
  default_dns_challenge     = try(local.effective_config.default_dns_challenge, {})

  certificate_specs = {
    for cert in try(local.effective_config.certificates, []) :
    cert.name => cert
  }

  access_list_specs = {
    for access_list in try(local.effective_config.access_lists, []) :
    access_list.name => access_list
  }

  proxy_host_specs = {
    for proxy_host in try(local.effective_config.proxy_hosts, []) :
    proxy_host.name => proxy_host
  }

  redirection_specs = {
    for redirection in try(local.effective_config.redirections, []) :
    redirection.name => redirection
  }

  stream_specs = {
    for stream in try(local.effective_config.streams, []) :
    stream.name => stream
  }
}
