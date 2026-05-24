locals {
  service_name_prefix = "qbittorrent-exporter"
  internal_port       = 8090
  instance_keys       = sort(keys(var.instances))

  qbittorrent_instance_types = {
    for name in local.instance_keys : name => (
      startswith(name, "movie-") ? "movie" :
      startswith(name, "television-") ? "television" :
      startswith(name, "cross-seed-") ? "cross-seed" :
      name
    )
  }

  per_instance_env = {
    for name, instance in var.instances : name => {
      for key, value in merge(
        var.env,
        { QBITTORRENT_BASE_URL = instance.base_url },
      ) : key => trimspace(tostring(value))
    }
  }
}
