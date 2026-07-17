# locals.tf
# Single source of truth for Graylog Swarm service values (resources read local.* only).

locals {
  env                          = var.env
  dns_nameservers              = var.dns_nameservers
  placement                    = var.placement
  swarm_docker_provider_config = var.swarm_docker_provider_config

  published_port_ui         = var.published_port_ui
  published_port_syslog_tcp = var.published_port_syslog_tcp
  published_port_gelf_tcp   = var.published_port_gelf_tcp

  network_name         = "graylog-app"
  mongodb_network_name = "graylog-mongodb"

  datanode_service_name  = "graylog-datanode"
  datanode_network_alias = "datanode"
  datanode_hostname      = "datanode"
  datanode_volume_name   = "graylog-datanode-data"
  datanode_data_mount    = "/var/lib/graylog-datanode"
  datanode_node_id_file  = "/var/lib/graylog-datanode/node-id"

  server_service_name  = "graylog"
  server_network_alias = "graylog"
  server_hostname      = "server"
  server_volume_name   = "graylog-server-data"
  server_data_mount    = "/usr/share/graylog/data"
  server_node_id_file  = "/usr/share/graylog/data/data/node-id"
  server_command       = ["/usr/bin/tini", "--", "/docker-entrypoint.sh"]

  ui_target_port     = 9000
  syslog_target_port = 5140
  gelf_target_port   = 12201

  graylog_password_secret    = local.env.GRAYLOG_PASSWORD_SECRET
  graylog_root_password      = local.env.GRAYLOG_ROOT_PASSWORD_SHA2
  graylog_http_bind          = coalesce(try(local.env.GRAYLOG_HTTP_BIND_ADDRESS, null), "0.0.0.0:9000")
  graylog_http_external      = local.env.GRAYLOG_HTTP_EXTERNAL_URI
  graylog_mongodb_uri        = coalesce(try(local.env.GRAYLOG_MONGODB_URI, null), "mongodb://mongodb:27017/graylog")
  graylog_selfsigned_startup = "true"

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
