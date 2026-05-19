locals {
  service_name  = "mcp-rag"
  internal_port = 8080

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  env_file_pairs = [
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) : {
      key   = trimspace(split("=", trimspace(raw_line))[0])
      value = trimspace(join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line))))))
    }
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  ]
  env_passthrough_keys = toset([
    "LOG_LEVEL",
    "MCP_RAG_API_KEY",
    "MCP_RAG_ENGINE_TIMEOUT_SEC",
    "MCP_RAG_HEALTHCHECK_HOST",
    "MCP_RAG_HEALTHCHECK_PATH",
    "MCP_RAG_HEALTHCHECK_TIMEOUT",
    "MCP_RAG_LOG_LEVEL",
    "RAG_ENGINE_API_KEY",
    "RAG_ENGINE_BASE_URL",
  ])
  parsed_env = {
    for pair in local.env_file_pairs : pair.key => pair.value
    if contains(local.env_passthrough_keys, pair.key)
  }
  default_env = {
    TZ                         = var.timezone
    LOG_LEVEL                  = var.log_level
    MCP_RAG_LOG_LEVEL          = var.log_level
    RAG_ENGINE_BASE_URL        = var.rag_engine_base_url
    MCP_RAG_ENGINE_TIMEOUT_SEC = tostring(var.request_timeout_seconds)
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)
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
    for a in local.docker_registry_auths : a
    if lower(trimspace(replace(replace(try(a.address, "ghcr.io"), "https://", ""), "http://", ""))) == local.pull_normalized_registry_host
  ]
  pull_selected_auth = length(local.pull_auth_matches) > 0 ? local.pull_auth_matches[0] : (
    length(local.docker_registry_auths) == 1 ? local.docker_registry_auths[0] : null
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

locals {
  docker_registry_auths = coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])
}
