locals {
  service_name  = "chromadb"
  network_name  = "chromadb"
  internal_port = 8000
  # Pin matches chroma-core/chroma GitHub release (not Docker "latest"); bump when upgrading Chroma.
  chromadb_image          = "chromadb/chroma:1.5.9"
  chromadb_data_volume    = "chromadb-data"
  chromadb_published_port = 8000
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
