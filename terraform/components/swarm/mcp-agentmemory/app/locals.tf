locals {
  agentmemory_env = {
    for key, value in var.env : key => value
    if contains(["AGENTMEMORY_SECRET", "AGENTMEMORY_DATA_DIR", "AGENTMEMORY_HMAC_FILE"], key)
  }

  mcp_agentmemory_env = merge(
    {
      AGENTMEMORY_URL = "http://agentmemory:3111"
    },
    {
      for key, value in var.env : key => value
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
}
