locals {
  service_name_prefix = "qbittorrent-exporter"
  internal_port       = 8090

  default_qbittorrent_hosts = {
    "movie-0"        = "https://qbittorrent.movie.0.nodadyoushutup.com"
    "movie-1"        = "https://qbittorrent.movie.1.nodadyoushutup.com"
    "movie-2"        = "https://qbittorrent.movie.2.nodadyoushutup.com"
    "movie-3"        = "https://qbittorrent.movie.3.nodadyoushutup.com"
    "movie-4"        = "https://qbittorrent.movie.4.nodadyoushutup.com"
    "movie-5"        = "https://qbittorrent.movie.5.nodadyoushutup.com"
    "movie-6"        = "https://qbittorrent.movie.6.nodadyoushutup.com"
    "movie-7"        = "https://qbittorrent.movie.7.nodadyoushutup.com"
    "movie-8"        = "https://qbittorrent.movie.8.nodadyoushutup.com"
    "movie-9"        = "https://qbittorrent.movie.9.nodadyoushutup.com"
    "movie-10"       = "https://qbittorrent.movie.10.nodadyoushutup.com"
    "television-0"   = "https://qbittorrent.television.0.nodadyoushutup.com"
    "television-1"   = "https://qbittorrent.television.1.nodadyoushutup.com"
    "television-2"   = "https://qbittorrent.television.2.nodadyoushutup.com"
    "cross-seed-ab"  = "https://qbittorrent.cross-seed.ab.nodadyoushutup.com"
    "cross-seed-ant" = "https://qbittorrent.cross-seed.ant.nodadyoushutup.com"
    "cross-seed-ath" = "https://qbittorrent.cross-seed.ath.nodadyoushutup.com"
    "cross-seed-bhd" = "https://qbittorrent.cross-seed.bhd.nodadyoushutup.com"
    "cross-seed-blu" = "https://qbittorrent.cross-seed.blu.nodadyoushutup.com"
    "cross-seed-cg"  = "https://qbittorrent.cross-seed.cg.nodadyoushutup.com"
    "cross-seed-hdb" = "https://qbittorrent.cross-seed.hdb.nodadyoushutup.com"
    "cross-seed-kg"  = "https://qbittorrent.cross-seed.kg.nodadyoushutup.com"
    "cross-seed-sc"  = "https://qbittorrent.cross-seed.sc.nodadyoushutup.com"
    "upload"         = "https://qbittorrent.upload.nodadyoushutup.com"
    "books"          = "https://qbittorrent.books.nodadyoushutup.com"
    "xxx"            = "https://qbittorrent.xxx.nodadyoushutup.com"
    "freeleech"      = "https://qbittorrent.freeleech.nodadyoushutup.com"
  }

  all_qbittorrent_hosts = merge(local.default_qbittorrent_hosts, var.qbittorrent_hosts)
  qbittorrent_hosts = length(var.qbittorrent_hosts_only) > 0 ? {
    for name, base_url in local.all_qbittorrent_hosts :
    name => base_url if contains(var.qbittorrent_hosts_only, name)
  } : local.all_qbittorrent_hosts
  instance_keys = sort(keys(local.qbittorrent_hosts))

  # movie-*, television-*, cross-seed-* → type label for Prometheus/Grafana filters.
  qbittorrent_instance_types = {
    for name in local.instance_keys : name => (
      startswith(name, "movie-") ? "movie" :
      startswith(name, "television-") ? "television" :
      startswith(name, "cross-seed-") ? "cross-seed" :
      name
    )
  }

  instance_ports = {
    for i, name in local.instance_keys : name => var.exporter_port_base + i
  }

  common_exporter_env = {
    EXPORTER_HOST           = "0.0.0.0"
    EXPORTER_PORT           = tostring(local.internal_port)
    ENABLE_HIGH_CARDINALITY = var.enable_high_cardinality ? "true" : "false"
    INSECURE_SKIP_VERIFY    = var.insecure_skip_verify ? "true" : "false"
    LOG_LEVEL               = var.log_level
    ENABLE_TRACKER          = var.enable_tracker ? "true" : "false"
    QBITTORRENT_USERNAME    = var.qbittorrent_username
  }

  per_instance_env = {
    for name, base_url in local.qbittorrent_hosts : name => {
      for key, value in merge(
        local.common_exporter_env,
        { QBITTORRENT_BASE_URL = base_url },
        var.env,
      ) : key => trimspace(tostring(value))
    }
  }
}

locals {
  pull_ref                      = var.image_reference
  pull_at_stripped              = split("@", local.pull_ref)[0]
  pull_colon_parts              = split(":", local.pull_at_stripped)
  pull_image_repository         = length(local.pull_colon_parts) <= 1 ? local.pull_at_stripped : join(":", slice(local.pull_colon_parts, 0, length(local.pull_colon_parts) - 1))
  pull_repo_slash_parts         = split("/", local.pull_image_repository)
  pull_registry_host            = length(local.pull_repo_slash_parts) >= 2 && (strcontains(local.pull_repo_slash_parts[0], ".") || strcontains(local.pull_repo_slash_parts[0], ":") || lower(local.pull_repo_slash_parts[0]) == "localhost") ? local.pull_repo_slash_parts[0] : "docker.io"
  pull_normalized_registry_host = lower(trimspace(local.pull_registry_host))
  pull_auth_matches = [
    for a in coalesce(try(var.swarm_docker_provider_config.registry_auths, null), []) : a
    if lower(trimspace(replace(replace(try(a.address, "ghcr.io"), "https://", ""), "http://", ""))) == local.pull_normalized_registry_host
  ]
  pull_selected_auth = length(local.pull_auth_matches) > 0 ? local.pull_auth_matches[0] : (
    length(coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])) == 1 ? coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])[0] : null
  )
  pull_server_address = local.pull_selected_auth == null ? "" : trimspace(replace(replace(try(local.pull_selected_auth.address, "ghcr.io"), "https://", ""), "http://", ""))
  docker_service_pull_auth_map = local.pull_selected_auth == null ? {} : {
    pull = {
      server_address = local.pull_server_address
      username       = local.pull_selected_auth.username
      password       = local.pull_selected_auth.password
    }
  }
}
