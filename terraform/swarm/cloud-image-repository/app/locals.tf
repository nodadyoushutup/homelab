locals {
  service_name      = "cloud-image-repository"
  network_name      = "cloud-image-repository"
  data_volume_name  = "webserver-image-data" # legacy Docker volume name retains existing qcow2 data
  internal_port     = 8080
  published_port    = 18088
  data_mount_target = "/srv/cloud-image-repository/data"
  ui_mount_target   = "/srv/cloud-image-repository/ui"
  index_html        = file("${path.module}/index.html")
  app_js            = file("${path.module}/app.js")
  favicon_svg       = file("${path.module}/favicon.svg")
  server_py         = file("${path.module}/server.py")
  index_html_hash   = substr(sha256(local.index_html), 0, 12)
  app_js_hash       = substr(sha256(local.app_js), 0, 12)
  favicon_svg_hash  = substr(sha256(local.favicon_svg), 0, 12)
  server_py_hash    = substr(sha256(local.server_py), 0, 12)
  service_config_hash = substr(
    sha256(
      join(
        "\n",
        [
          local.index_html,
          local.app_js,
          local.favicon_svg,
          local.server_py,
        ],
      ),
    ),
    0,
    12,
  )
  app_force_update = parseint(substr(local.service_config_hash, 0, 8), 16)
  image_reference  = "python:3.12.11-alpine3.22"
}




locals {
  provider_config = merge(var.swarm_docker_provider_config, var.provider_config)
  docker_registry_auths = (
    try(local.provider_config.registry_auths, null) != null
    ? local.provider_config.registry_auths
    : (
      try(local.provider_config.registry_auth, null) != null
      ? [local.provider_config.registry_auth]
      : []
    )
  )
}
