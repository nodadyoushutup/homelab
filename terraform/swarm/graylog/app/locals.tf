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

  graylog_password_secret = var.env.GRAYLOG_PASSWORD_SECRET
  graylog_root_password   = var.env.GRAYLOG_ROOT_PASSWORD_SHA2
  graylog_http_bind       = coalesce(try(var.env.GRAYLOG_HTTP_BIND_ADDRESS, null), "0.0.0.0:9000")
  graylog_http_external   = var.env.GRAYLOG_HTTP_EXTERNAL_URI
  graylog_mongodb_uri     = coalesce(try(var.env.GRAYLOG_MONGODB_URI, null), "mongodb://mongodb:27017/graylog")
}
