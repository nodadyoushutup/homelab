# locals.tf
# Single source of truth for mcp-agentmemory Swarm service values (resources read local.* only).

locals {
  dns_nameservers              = var.dns_nameservers
  env                          = var.env
  placement                    = var.placement
  replicas                     = var.replicas
  swarm_docker_provider_config = var.swarm_docker_provider_config

  network_name = "mcp-agentmemory"

  agentmemory_service_name  = "agentmemory"
  agentmemory_network_alias = "agentmemory"
  agentmemory_volume_name   = "agentmemory-data"
  agentmemory_data_mount    = "/data"

  mcp_service_name   = "mcp-agentmemory"
  mcp_network_alias  = "mcp-agentmemory"
  mcp_target_port    = 8087
  mcp_published_port = 18212
  mcp_upstream_url   = "http://agentmemory:3111"

  agentmemory_env = {
    for key, value in local.env : key => value
    if contains(["AGENTMEMORY_SECRET", "AGENTMEMORY_DATA_DIR", "AGENTMEMORY_HMAC_FILE"], key)
  }

  mcp_agentmemory_env = merge(
    {
      AGENTMEMORY_URL = local.mcp_upstream_url
    },
    {
      for key, value in local.env : key => value
      if contains(
        [
          "AGENTMEMORY_SECRET",
          "AGENTMEMORY_URL",
          "MCP_AGENTMEMORY_API_KEY",
          "MCP_AGENTMEMORY_HOST",
          "MCP_AGENTMEMORY_LISTEN_PORT",
          "MCP_AGENTMEMORY_UPSTREAM_PORT",
        ],
        key
      )
    }
  )

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
